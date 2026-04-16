import importlib.util
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
ENFORCER_PATH = REPO_ROOT / "images" / "proxy" / "addons" / "enforcer.py"
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
    def __init__(self, host, scheme="http", method="GET", path="/"):
        self.host = host
        self.scheme = scheme
        self.method = method
        self.path = path


class FakeFlow:
    def __init__(self, host, scheme="http", method="GET", path="/"):
        self.request = FakeRequest(host, scheme=scheme, method=method, path=path)
        self.response = None
        self.error = None
        self.metadata = {}


class FakeResponse:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self.body = body


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
        self.assertIn('"path": "/v1/models"', log_output)

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


if __name__ == "__main__":
    unittest.main()
