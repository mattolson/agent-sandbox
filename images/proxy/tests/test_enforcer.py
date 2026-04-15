import importlib.util
import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
ENFORCER_PATH = REPO_ROOT / "images" / "proxy" / "addons" / "enforcer.py"
FIXED_TIME = datetime(2026, 4, 14, 5, 45, tzinfo=timezone.utc)


def load_enforcer_module():
    loader = SourceFileLoader("enforcer_module", str(ENFORCER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
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

    def test_allowlist_sorts_host_records_by_specificity(self):
        allowlist = self.enforcer_module.HostAllowlist.from_policy_data(
            {
                "domains": [
                    "*.github.com",
                    {"host": "*.api.github.com"},
                    {"host": "api.github.com"},
                ]
            }
        )

        self.assertEqual(
            [record["host"] for record in allowlist.domain_records],
            ["api.github.com", "*.api.github.com", "*.github.com"],
        )

    def test_allowlist_matches_exact_and_wildcard_hosts_case_insensitively(self):
        allowlist = self.enforcer_module.HostAllowlist.from_policy_data(
            {"domains": ["api.openai.com", "*.github.com"]}
        )

        self.assertTrue(allowlist.is_allowed("api.openai.com"))
        self.assertTrue(allowlist.is_allowed("API.OPENAI.COM"))
        self.assertTrue(allowlist.is_allowed("github.com"))
        self.assertTrue(allowlist.is_allowed("api.github.com"))
        self.assertFalse(allowlist.is_allowed("api.notgithub.com"))

    def test_allowlist_rejects_non_list_domains_field(self):
        with self.assertRaises(self.enforcer_module.PolicyError) as context:
            self.enforcer_module.HostAllowlist.from_policy_data({"domains": "github.com"})

        self.assertIn("field 'domains' must be a YAML list", str(context.exception))

    def test_enforce_mode_loads_policy_from_file_and_logs_source_path(self):
        logger_output = io.StringIO()
        logger = self.make_logger(logger_output)

        with tempfile.TemporaryDirectory() as tempdir:
            policy_path = Path(tempdir) / "policy.yaml"
            policy_path.write_text(
                """
domains:
  - api.openai.com
  - "*.github.com"
""",
                encoding="utf-8",
            )

            enforcer = self.enforcer_module.PolicyEnforcer(
                mode="enforce",
                policy_path=str(policy_path),
                logger=logger,
                response_factory=self.make_response,
            )

        self.assertEqual(enforcer.allowed_exact, {"api.openai.com"})
        self.assertEqual(enforcer.allowed_wildcards, ["github.com"])
        self.assertEqual(
            [record["host"] for record in enforcer.domain_records],
            ["api.openai.com", "*.github.com"],
        )
        self.assertIn(f"Policy loaded from {policy_path}", logger_output.getvalue())

    def test_http_connect_blocks_disallowed_hosts_in_enforce_mode(self):
        logger_output = io.StringIO()
        allowlist = self.enforcer_module.HostAllowlist.from_policy_data(
            {"domains": ["api.openai.com"]}
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            allowlist=allowlist,
            logger=self.make_logger(logger_output),
            response_factory=self.make_response,
        )
        flow = FakeFlow("blocked.example", scheme="https", method="CONNECT")

        enforcer.http_connect(flow)

        self.assertIsNotNone(flow.response)
        self.assertEqual(flow.response.status_code, 403)
        self.assertEqual(flow.response.body, "Blocked by proxy policy: blocked.example")
        self.assertIn('"host": "blocked.example"', logger_output.getvalue())
        self.assertIn('"action": "blocked"', logger_output.getvalue())

    def test_request_blocks_only_plain_http(self):
        allowlist = self.enforcer_module.HostAllowlist.from_policy_data(
            {"domains": ["api.openai.com"]}
        )
        enforcer = self.enforcer_module.PolicyEnforcer(
            mode="enforce",
            allowlist=allowlist,
            logger=self.make_logger(io.StringIO()),
            response_factory=self.make_response,
        )

        http_flow = FakeFlow("blocked.example", scheme="http", method="GET", path="/v1")
        https_flow = FakeFlow("blocked.example", scheme="https", method="GET", path="/v1")

        enforcer.request(http_flow)
        enforcer.request(https_flow)

        self.assertIsNotNone(http_flow.response)
        self.assertEqual(http_flow.response.status_code, 403)
        self.assertIsNone(https_flow.response)

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
