import asyncio
import importlib.util
import io
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
