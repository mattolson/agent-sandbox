import asyncio
import base64
import importlib.util
import io
import json
import os
import signal
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
ENFORCER_PATH = REPO_ROOT / "images" / "proxy" / "addons" / "enforcer.py"
RENDER_POLICY_PATH = REPO_ROOT / "images" / "proxy" / "render-policy"
FIXED_TIME = datetime(2026, 4, 15, 6, 15, tzinfo=timezone.utc)


def load_enforcer_module():
    loader = SourceFileLoader("enforcer_module", str(ENFORCER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    with mock.patch.dict(os.environ, {"PROXY_MODE": "log"}, clear=False):
        with redirect_stdout(io.StringIO()):
            loader.exec_module(module)
    return module


class FakeRequest:
    def __init__(self, host, scheme="http", method="GET", path="/", headers=None):
        self.host = host
        self.scheme = scheme
        self.method = method
        self.path = path
        self.headers = dict(headers or {})
        self.stream = False


class FakeFlow:
    def __init__(self, host, scheme="http", method="GET", path="/", headers=None):
        self.request = FakeRequest(
            host,
            scheme=scheme,
            method=method,
            path=path,
            headers=headers,
        )
        self.response = None
        self.error = None
        self.metadata = {}


class FakeResponse:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self.body = body
        self.stream = False


class PolicyEnforcerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enforcer_module = load_enforcer_module()

    def make_logger(self, stream, log_level="normal"):
        return self.enforcer_module.JsonLogger(
            log_level=log_level,
            stream=stream,
            clock=lambda: FIXED_TIME,
        )

    def make_response(self, status_code, body):
        return FakeResponse(status_code, body)

    def matcher_from_domains(self, domains):
        return self.enforcer_module.PolicyMatcher.from_policy_data({"domains": domains})

    def secret_resolver_factory(self, secrets):
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        root = Path(tempdir.name)
        for name, value in secrets.items():
            (root / name).write_text(value, encoding="utf-8")
        return lambda: self.enforcer_module.SecretResolver.from_source(f"file:{root}")

    def transformed_domain(
        self,
        *,
        transform_type="bearer",
        username=None,
        on_existing_header="fail",
        methods=("GET",),
        path="/v1/models",
    ):
        transform = {"type": transform_type}
        if username is not None:
            transform["username"] = username
        return {
            "host": "api.openai.com",
            "rules": [
                {
                    "schemes": ["https"],
                    "methods": list(methods),
                    "path": {"exact": path},
                    "transform": {
                        "request": {
                            "headers": {
                                "Authorization": {
                                    "secret": "openai-api-token",
                                    "transform": transform,
                                },
                            },
                            "on_existing_header": on_existing_header,
                        },
                    },
                }
            ],
        }

    def parse_events(self, stream):
        events = []
        for line in stream.getvalue().splitlines():
            events.append(json.loads(line))
        return events

    def test_enforce_mode_loads_policy_from_file_and_logs_source_path(self):
        logger_output = io.StringIO()
        logger = self.make_logger(logger_output)

        with tempfile.TemporaryDirectory() as tempdir:
            policy_path = Path(tempdir) / "policy.yaml"
            policy_path.write_text(
                """
domains:
  - host: api.openai.com
    rules:
      - schemes: [https]
  - host: "*.github.com"
    rules:
      - schemes: [http, https]
""",
                encoding="utf-8",
            )

            enforcer = self.enforcer_module.PolicyEnforcer(
                mode="enforce",
                policy_path=str(policy_path),
                logger=logger,
                response_factory=self.make_response,
            )

        self.assertEqual(enforcer.exact_host_count, 1)
        self.assertEqual(enforcer.wildcard_host_count, 1)
        self.assertEqual(
            [record["host"] for record in enforcer.domain_records],
            ["api.openai.com", "*.github.com"],
        )
        self.assertIn(f"Policy loaded from {policy_path}", logger_output.getvalue())

    def test_http_connect_blocks_disallowed_hosts_in_enforce_mode(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(["api.openai.com"])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow("blocked.example", scheme="https", method="CONNECT")

        enforcer.http_connect(flow)

        self.assertIsNotNone(flow.response)
        self.assertEqual(flow.response.status_code, 403)
        self.assertEqual(flow.response.body, "Blocked by proxy policy: blocked.example")
        self.assertIn('"phase": "connect"', logger_output.getvalue())
        self.assertIn('"reason": "host_not_allowed"', logger_output.getvalue())

    def test_http_connect_allows_hosts_that_require_request_inspection(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"prefix": "/v1/models"},
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="CONNECT")

        enforcer.http_connect(flow)

        self.assertIsNone(flow.response)

    def test_request_blocks_when_no_rule_matches_and_response_does_not_relog_it_as_allowed(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"exact": "/v1/models"},
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="POST", path="/v1/models")

        enforcer.request(flow)
        enforcer.response(flow)

        self.assertIsNotNone(flow.response)
        self.assertEqual(flow.response.status_code, 403)
        log_output = logger_output.getvalue()
        self.assertIn('"reason": "no_rule_matched"', log_output)
        self.assertNotIn('"status": 403', log_output)

    def test_requestheaders_blocks_before_request_body_streaming(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"exact": "/v1/models"},
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="POST", path="/v1/models")
        flow.request.stream = True

        enforcer.requestheaders(flow)
        enforcer.request(flow)

        self.assertIsNotNone(flow.response)
        self.assertEqual(flow.response.status_code, 403)
        self.assertFalse(flow.request.stream)
        log_output = logger_output.getvalue()
        self.assertIn('"reason": "no_rule_matched"', log_output)
        self.assertEqual(log_output.count('"action": "blocked"'), 1)

    def test_responseheaders_streams_response_body(self):
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(io.StringIO()),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")
        flow.response = FakeResponse(200, "ok")

        enforcer.responseheaders(flow)

        self.assertTrue(flow.response.stream)

    def test_response_logs_allowed_request_with_match_reason_and_status(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"exact": "/v1/models"},
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models?limit=10")

        enforcer.request(flow)
        self.assertIsNone(flow.response)
        flow.response = FakeResponse(200, "ok")
        enforcer.response(flow)

        log_output = logger_output.getvalue()
        self.assertIn('"action": "allowed"', log_output)
        self.assertIn('"reason": "request_rule_matched"', log_output)
        self.assertIn('"status": 200', log_output)
        self.assertIn('"path": "/v1/models?limit=10"', log_output)

    def test_blocked_request_log_includes_query_string(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "github.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"exact": "/owner/repo.git/info/refs"},
                            "query": {
                                "exact": {
                                    "service": ["git-upload-pack"],
                                }
                            },
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow(
            "github.com",
            scheme="https",
            method="GET",
            path="/owner/repo.git/info/refs?service=git-receive-pack",
        )

        enforcer.request(flow)

        event = self.parse_events(logger_output)[-1]
        self.assertEqual(event["action"], "blocked")
        self.assertEqual(event["reason"], "no_rule_matched")
        self.assertEqual(
            event["path"],
            "/owner/repo.git/info/refs?service=git-receive-pack",
        )

    def test_request_injects_bearer_header_for_matching_rule(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain()])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "sentinel-secret-token"}
            ),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.requestheaders(flow)

        self.assertIsNone(flow.response)
        self.assertEqual(
            flow.request.headers["Authorization"],
            "Bearer sentinel-secret-token",
        )
        log_output = logger_output.getvalue()
        self.assertIn('"type": "header_injection"', log_output)
        self.assertIn('"secret": "openai-api-token"', log_output)
        self.assertIn('"matched_rule_index": 0', log_output)
        self.assertNotIn("sentinel-secret-token", log_output)
        self.assertNotIn(
            "sentinel-secret-token",
            json.dumps(flow.metadata, sort_keys=True),
        )

    def test_header_injection_log_includes_query_string(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain()])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "sentinel-secret-token"}
            ),
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models?limit=10",
        )

        enforcer.requestheaders(flow)

        event = [
            item for item in self.parse_events(logger_output)
            if item.get("type") == "header_injection"
        ][0]
        self.assertEqual(event["path"], "/v1/models?limit=10")

    def test_request_injects_basic_header_for_matching_rule(self):
        matcher = self.matcher_from_domains(
            [
                self.transformed_domain(
                    transform_type="basic",
                    username="x-access-token",
                )
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "github-token"}
            ),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.request(flow)

        encoded = base64.b64encode(b"x-access-token:github-token").decode("ascii")
        self.assertEqual(flow.request.headers["Authorization"], f"Basic {encoded}")

    def test_unmatched_request_does_not_inject_or_construct_resolver(self):
        def unexpected_resolver():
            raise AssertionError("resolver should not be constructed")

        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain(methods=("POST",))])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=unexpected_resolver,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.request(flow)

        self.assertIsNotNone(flow.response)
        self.assertNotIn("Authorization", flow.request.headers)
        self.assertIn('"reason": "no_rule_matched"', logger_output.getvalue())

    def test_untransformed_rule_does_not_require_secret_source(self):
        def unexpected_resolver():
            raise AssertionError("resolver should not be constructed")

        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"exact": "/v1/models"},
                        }
                    ],
                }
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
            secret_resolver_factory=unexpected_resolver,
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.request(flow)

        self.assertIsNone(flow.response)
        self.assertNotIn("Authorization", flow.request.headers)

    def test_existing_header_fails_closed_by_default_without_resolving_secret(self):
        def unexpected_resolver():
            raise AssertionError("resolver should not be constructed")

        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain()])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=unexpected_resolver,
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models",
            headers={"authorization": "user-supplied"},
        )

        enforcer.requestheaders(flow)

        self.assertIsNotNone(flow.response)
        self.assertEqual(flow.response.status_code, 403)
        self.assertEqual(flow.request.headers["authorization"], "user-supplied")
        log_output = logger_output.getvalue()
        self.assertIn('"reason": "header_injection_failed"', log_output)
        self.assertIn('"detail": "existing_header_present"', log_output)
        self.assertIn('"header": "Authorization"', log_output)

    def test_existing_header_replace_overwrites_case_insensitively(self):
        matcher = self.matcher_from_domains(
            [self.transformed_domain(on_existing_header="replace")]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "replacement-token"}
            ),
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models",
            headers={"authorization": "old-token"},
        )

        enforcer.request(flow)

        self.assertIsNone(flow.response)
        self.assertNotIn("authorization", flow.request.headers)
        self.assertEqual(
            flow.request.headers["Authorization"],
            "Bearer replacement-token",
        )

    def test_existing_fake_authorization_replace_can_render_basic_header(self):
        matcher = self.matcher_from_domains(
            [
                self.transformed_domain(
                    transform_type="basic",
                    username="x-access-token",
                    on_existing_header="replace",
                )
            ]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "real-github-token"}
            ),
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models",
            headers={"Authorization": "Basic fake"},
        )

        enforcer.request(flow)

        encoded = base64.b64encode(b"x-access-token:real-github-token").decode("ascii")
        self.assertIsNone(flow.response)
        self.assertEqual(flow.request.headers["Authorization"], f"Basic {encoded}")

    def test_default_secret_source_fails_closed_when_default_root_missing(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain()])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=lambda: self.enforcer_module.SecretResolver.from_env({}),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.request(flow)

        self.assertIsNotNone(flow.response)
        log_output = logger_output.getvalue()
        self.assertIn('"reason": "header_injection_failed"', log_output)
        self.assertIn('"detail": "secret_resolution_failed"', log_output)
        self.assertIn("Secret source root does not exist", log_output)
        self.assertIn("/run/secrets/agentbox", log_output)

    def test_missing_secret_file_fails_closed_without_leaking_values(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains([self.transformed_domain()])
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory({}),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.requestheaders(flow)

        self.assertIsNotNone(flow.response)
        log_output = logger_output.getvalue()
        self.assertIn('"detail": "secret_resolution_failed"', log_output)
        self.assertIn('"secret": "openai-api-token"', log_output)
        self.assertNotIn("sentinel-secret-token", log_output)
        self.assertNotIn("Authorization", flow.request.headers)

    def test_requestheaders_and_request_do_not_inject_twice(self):
        logger_output = io.StringIO()
        matcher = self.matcher_from_domains(
            [self.transformed_domain(on_existing_header="fail")]
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
            secret_resolver_factory=self.secret_resolver_factory(
                {"openai-api-token": "single-injection-token"}
            ),
        )
        flow = FakeFlow("api.openai.com", scheme="https", method="GET", path="/v1/models")

        enforcer.requestheaders(flow)
        enforcer.request(flow)

        self.assertIsNone(flow.response)
        self.assertEqual(
            flow.request.headers["Authorization"],
            "Bearer single-injection-token",
        )
        self.assertEqual(logger_output.getvalue().count('"type": "header_injection"'), 1)

    def test_log_mode_never_blocks_requests(self):
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(io.StringIO()),
        )

        connect_flow = FakeFlow("blocked.example", scheme="https", method="CONNECT")
        request_flow = FakeFlow("blocked.example", scheme="http", method="GET", path="/")

        enforcer.http_connect(connect_flow)
        enforcer.request(request_flow)

        self.assertIsNone(connect_flow.response)
        self.assertIsNone(request_flow.response)

    def test_log_mode_response_log_includes_query_string(self):
        logger_output = io.StringIO()
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(logger_output),
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models?limit=10",
        )
        flow.response = FakeResponse(200, "ok")

        enforcer.response(flow)

        event = self.parse_events(logger_output)[-1]
        self.assertEqual(event["path"], "/v1/models?limit=10")

    def test_error_log_includes_query_string(self):
        logger_output = io.StringIO()
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(logger_output),
        )
        flow = FakeFlow(
            "api.openai.com",
            scheme="https",
            method="GET",
            path="/v1/models?limit=10",
        )
        flow.error = RuntimeError("upstream closed")

        enforcer.error(flow)

        event = self.parse_events(logger_output)[-1]
        self.assertEqual(event["path"], "/v1/models?limit=10")
        self.assertEqual(event["error"], "upstream closed")


class PolicyEnforcerReloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enforcer_module = load_enforcer_module()

    def make_logger(self, stream, log_level="normal"):
        return self.enforcer_module.JsonLogger(
            log_level=log_level,
            stream=stream,
            clock=lambda: FIXED_TIME,
        )

    def build_enforcer(self, initial_domains, renderer, logger_output=None):
        if logger_output is None:
            logger_output = io.StringIO()
        matcher = self.enforcer_module.PolicyMatcher.from_policy_data(
            {"domains": initial_domains}
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output),
            response_factory=FakeResponse,
            reload_renderer=renderer,
        )
        return enforcer, logger_output

    def test_render_policy_loader_does_not_accumulate_sys_path_entries(self):
        original_sys_path = list(sys.path)
        try:
            self.enforcer_module._load_render_policy_module(RENDER_POLICY_PATH)
            self.enforcer_module._load_render_policy_module(RENDER_POLICY_PATH)

            self.assertEqual(sys.path, original_sys_path)
        finally:
            sys.path[:] = original_sys_path

    def test_reload_swaps_matcher_and_emits_applied_event(self):
        def renderer():
            return {"domains": ["example.com", "*.example.net"]}

        enforcer, logger_output = self.build_enforcer(
            initial_domains=["old.example"],
            renderer=renderer,
        )

        asyncio.run(enforcer.reload())

        hosts = [record.host for record in enforcer.matcher.host_records]
        self.assertEqual(hosts, ["example.com", "*.example.net"])
        self.assertEqual(
            [record["host"] for record in enforcer.domain_records],
            ["example.com", "*.example.net"],
        )
        self.assertEqual(enforcer.exact_host_count, 1)
        self.assertEqual(enforcer.wildcard_host_count, 1)

        log_output = logger_output.getvalue()
        self.assertIn('"type": "reload"', log_output)
        self.assertIn('"action": "applied"', log_output)
        self.assertIn('"host_records": 2', log_output)
        self.assertIn('"exact_host_count": 1', log_output)
        self.assertIn('"wildcard_host_count": 1', log_output)

    def test_reload_keeps_prior_matcher_when_render_raises(self):
        def renderer():
            raise RuntimeError("render boom")

        enforcer, logger_output = self.build_enforcer(
            initial_domains=["keep.example"],
            renderer=renderer,
        )
        prior_matcher = enforcer.matcher

        asyncio.run(enforcer.reload())

        self.assertIs(enforcer.matcher, prior_matcher)
        self.assertEqual(
            [record["host"] for record in enforcer.domain_records],
            ["keep.example"],
        )

        log_output = logger_output.getvalue()
        self.assertIn('"action": "rejected"', log_output)
        self.assertIn('"error": "render boom"', log_output)

    def test_reload_rejects_invalid_policy_and_keeps_prior_matcher(self):
        def renderer():
            return {"domains": [{"host": "bad.example"}]}  # rules required

        enforcer, logger_output = self.build_enforcer(
            initial_domains=["keep.example"],
            renderer=renderer,
        )
        prior_matcher = enforcer.matcher

        asyncio.run(enforcer.reload())

        self.assertIs(enforcer.matcher, prior_matcher)
        log_output = logger_output.getvalue()
        self.assertIn('"action": "rejected"', log_output)
        self.assertIn('"error"', log_output)

    def test_reload_is_noop_in_log_mode(self):
        calls = []

        def renderer():
            calls.append(1)
            return {"domains": []}

        logger_output = io.StringIO()
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(logger_output),
            reload_renderer=renderer,
        )

        asyncio.run(enforcer.reload())

        self.assertEqual(calls, [])
        self.assertNotIn('"type": "reload"', logger_output.getvalue())

    def test_reload_events_emit_even_in_quiet_mode(self):
        def renderer():
            return {"domains": ["new.example"]}

        logger_output = io.StringIO()
        matcher = self.enforcer_module.PolicyMatcher.from_policy_data(
            {"domains": ["old.example"]}
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            matcher=matcher,
            logger=self.make_logger(logger_output, log_level="quiet"),
            response_factory=FakeResponse,
            reload_renderer=renderer,
        )

        asyncio.run(enforcer.reload())

        self.assertIn('"action": "applied"', logger_output.getvalue())

    def test_concurrent_reloads_are_serialized(self):
        observed_in_flight = []
        started = threading.Event()
        release = threading.Event()

        def slow_renderer():
            started.set()
            release.wait(timeout=1.0)
            return {"domains": ["first.example"]}

        def quick_renderer():
            return {"domains": ["second.example"]}

        async def run():
            enforcer, _ = self.build_enforcer(
                initial_domains=["old.example"],
                renderer=slow_renderer,
            )
            first = asyncio.create_task(enforcer.reload())
            await asyncio.get_running_loop().run_in_executor(None, started.wait)
            enforcer.reload_renderer = quick_renderer
            second = asyncio.create_task(enforcer.reload())
            release.set()
            await first
            observed_in_flight.append(
                [record["host"] for record in enforcer.domain_records]
            )
            await second
            observed_in_flight.append(
                [record["host"] for record in enforcer.domain_records]
            )

        asyncio.run(run())

        self.assertEqual(observed_in_flight, [["first.example"], ["second.example"]])

    def test_running_installs_signal_handler_and_done_removes_it(self):
        def renderer():
            return {"domains": []}

        enforcer, _ = self.build_enforcer(
            initial_domains=["old.example"],
            renderer=renderer,
        )

        recorded = {}

        async def run():
            loop = asyncio.get_running_loop()
            original_add = loop.add_signal_handler
            original_remove = loop.remove_signal_handler

            def fake_add(sig, cb, *args):
                recorded["added"] = sig
                recorded["callback"] = cb
                return original_add(sig, cb, *args)

            def fake_remove(sig):
                recorded["removed"] = sig
                return original_remove(sig)

            with mock.patch.object(loop, "add_signal_handler", side_effect=fake_add):
                with mock.patch.object(loop, "remove_signal_handler", side_effect=fake_remove):
                    enforcer.running()
                    self.assertEqual(recorded["added"], signal.SIGHUP)
                    self.assertTrue(callable(recorded["callback"]))
                    enforcer.done()
                    self.assertEqual(recorded["removed"], signal.SIGHUP)

        asyncio.run(run())

    def test_running_is_noop_in_log_mode(self):
        logger_output = io.StringIO()
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="log",
            logger=self.make_logger(logger_output),
        )

        async def run():
            loop = asyncio.get_running_loop()
            with mock.patch.object(loop, "add_signal_handler") as add_handler:
                enforcer.running()
                add_handler.assert_not_called()

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
