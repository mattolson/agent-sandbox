"""End-to-end integration tests that drive the real mitmdump process.

Each test spawns a fresh proxy with a crafted policy file, then sends real HTTP
requests (or raw CONNECT probes) through it and asserts on both the HTTP
response and the structured decision log emitted to stdout.

The suite is skipped when `mitmdump` is not on PATH, so the plain unit-test
discover run still works in minimal environments. CI installs `mitmproxy` to
pull it in.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from .harness import FakeUpstream, mitmdump_available, spawn_proxy


def _yaml_policy(domains):
    return yaml.safe_dump({"domains": domains}, sort_keys=False)


def _skip_reason():
    return "mitmdump not available on PATH; install mitmproxy to run integration tests"


class _ProxyTestCase(unittest.TestCase):
    def spawn(self, policy_text, **kwargs):
        harness = spawn_proxy(policy_text, **kwargs)
        self.addCleanup(harness.terminate)
        return harness

    def upstream(self):
        upstream = FakeUpstream()
        upstream.start()
        self.addCleanup(upstream.stop)
        return upstream


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class ConnectPhaseTests(_ProxyTestCase):
    """CONNECT-phase decisions fire before any TLS handshake happens."""

    def test_https_host_allowed_is_not_blocked_at_connect(self):
        """Policy-allowed CONNECT must not emit a `phase: connect, blocked`
        log. We do not run a real HTTPS upstream, so the tunnel itself may
        fail later — that is outside the enforcer's decision surface."""
        harness = self.spawn(
            _yaml_policy(
                [{"host": "allowed.example", "rules": [{"schemes": ["https"]}]}]
            )
        )
        harness.send_connect_and_wait("allowed.example", 443)
        blocked = [
            event
            for event in harness.snapshot_events()
            if event.get("phase") == "connect"
            and event.get("action") == "blocked"
            and event.get("host") == "allowed.example"
        ]
        self.assertEqual(blocked, [])

    def test_https_host_not_in_policy_is_blocked_at_connect(self):
        harness = self.spawn(
            _yaml_policy(
                [{"host": "allowed.example", "rules": [{"schemes": ["https"]}]}]
            )
        )
        status_code, _ = harness.send_connect("denied.example")
        self.assertEqual(status_code, 403)
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "connect"
            and e.get("action") == "blocked"
            and e.get("host") == "denied.example"
        )
        self.assertEqual(event.get("reason"), "host_not_allowed")


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class RequestPhaseTests(_ProxyTestCase):
    """Method, path, and query constraints enforce after request headers arrive."""

    def setUp(self):
        self.upstream_server = self.upstream()
        self.upstream_url = self.upstream_server.url

    def _policy(self, rule_extra):
        rule = {"schemes": ["http"]}
        rule.update(rule_extra)
        return _yaml_policy([{"host": "127.0.0.1", "rules": [rule]}])

    def _secret_source(self, secrets):
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        root = Path(tempdir.name)
        for name, value in secrets.items():
            (root / name).write_text(value, encoding="utf-8")
        return f"file:{root}"

    def test_method_restriction_allows_get_and_blocks_post(self):
        harness = self.spawn(self._policy({"methods": ["GET"]}))
        status, _ = harness.send_get(self.upstream_url)
        self.assertEqual(status, 200)
        status, _ = harness.send_request("POST", self.upstream_url)
        self.assertEqual(status, 403)
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("action") == "blocked"
            and e.get("method") == "POST"
        )
        self.assertEqual(event.get("reason"), "no_rule_matched")

    def test_method_restriction_blocks_post_body_before_upstream(self):
        harness = self.spawn(self._policy({"methods": ["GET"]}))
        status, body = harness.send_request("POST", self.upstream_url, body=b"{}")
        self.assertEqual(status, 403)
        self.assertIn(b"Blocked by proxy policy", body)
        self.assertEqual(self.upstream_server.snapshot_requests(), [])
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("action") == "blocked"
            and e.get("method") == "POST"
        )
        self.assertEqual(event.get("reason"), "no_rule_matched")

    def test_path_prefix_restriction(self):
        harness = self.spawn(self._policy({"path": {"prefix": "/ok/"}}))
        status, _ = harness.send_get(self.upstream_url + "ok/hello")
        self.assertEqual(status, 200)
        status, _ = harness.send_get(self.upstream_url + "denied")
        self.assertEqual(status, 403)
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("action") == "blocked"
            and e.get("path", "").endswith("/denied")
        )
        self.assertEqual(event.get("reason"), "no_rule_matched")

    def test_query_exact_restriction(self):
        harness = self.spawn(
            self._policy(
                {"path": {"exact": "/search"}, "query": {"exact": {"version": ["v2"]}}}
            )
        )
        status, _ = harness.send_get(self.upstream_url + "search?version=v2")
        self.assertEqual(status, 200)
        status, _ = harness.send_get(self.upstream_url + "search?version=v1")
        self.assertEqual(status, 403)
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("action") == "blocked"
            and e.get("path", "").endswith("/search?version=v1")
        )
        self.assertEqual(event.get("reason"), "no_rule_matched")

    def test_header_injection_reaches_upstream_for_matched_rule(self):
        secret_source = self._secret_source({"service-token": "integration-secret"})
        harness = self.spawn(
            self._policy(
                {
                    "methods": ["GET"],
                    "path": {"exact": "/"},
                    "transform": {
                        "request": {
                            "headers": {
                                "Authorization": {
                                    "secret": "service-token",
                                    "transform": {"type": "bearer"},
                                },
                            },
                            "on_existing_header": "fail",
                        },
                    },
                }
            ),
            env_overrides={"AGENTBOX_SECRET_SOURCE": secret_source},
        )

        status, _ = harness.send_get(self.upstream_url)
        self.assertEqual(status, 200)
        requests = self.upstream_server.snapshot_requests()
        self.assertEqual(len(requests), 1)
        self.assertEqual(
            requests[0]["headers"].get("Authorization"),
            "Bearer integration-secret",
        )

        status, _ = harness.send_request("POST", self.upstream_url)
        self.assertEqual(status, 403)
        self.assertEqual(len(self.upstream_server.snapshot_requests()), 1)
        harness.wait_for_event(
            lambda e: e.get("type") == "header_injection"
            and e.get("action") == "applied"
            and e.get("headers", [{}])[0].get("secret") == "service-token"
        )
        self.assertNotIn("integration-secret", "\n".join(harness.snapshot_lines()))

    def test_header_injection_existing_header_conflict_blocks_before_upstream(self):
        secret_source = self._secret_source({"service-token": "integration-secret"})
        harness = self.spawn(
            self._policy(
                {
                    "methods": ["GET"],
                    "path": {"exact": "/"},
                    "transform": {
                        "request": {
                            "headers": {
                                "Authorization": {
                                    "secret": "service-token",
                                    "transform": {"type": "bearer"},
                                },
                            },
                            "on_existing_header": "fail",
                        },
                    },
                }
            ),
            env_overrides={"AGENTBOX_SECRET_SOURCE": secret_source},
        )

        status, _ = harness.send_get(
            self.upstream_url,
            headers={"Authorization": "Bearer user-supplied"},
        )
        self.assertEqual(status, 403)
        self.assertEqual(self.upstream_server.snapshot_requests(), [])
        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("reason") == "header_injection_failed"
        )
        self.assertEqual(event.get("detail"), "existing_header_present")
        self.assertEqual(event.get("secret"), "service-token")
        self.assertNotIn("integration-secret", "\n".join(harness.snapshot_lines()))


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class ReloadTests(_ProxyTestCase):
    """SIGHUP swaps the matcher atomically; a bad render keeps the old one."""

    def setUp(self):
        self.upstream_url = self.upstream().url

    def test_sighup_applied_swaps_policy(self):
        initial = _yaml_policy(
            [
                {
                    "host": "127.0.0.1",
                    "rules": [{"schemes": ["http"], "methods": ["GET"]}],
                }
            ]
        )
        harness = self.spawn(initial)
        status, _ = harness.send_request("POST", self.upstream_url)
        self.assertEqual(status, 403)

        harness.write_policy(
            _yaml_policy(
                [
                    {
                        "host": "127.0.0.1",
                        "rules": [{"schemes": ["http"], "methods": ["GET", "POST"]}],
                    }
                ]
            )
        )
        harness.reload()
        harness.wait_for_event(
            lambda e: e.get("type") == "reload" and e.get("action") == "applied"
        )

        status, _ = harness.send_request("POST", self.upstream_url)
        self.assertEqual(status, 200)

    def test_sighup_rejected_keeps_previous_policy(self):
        initial = _yaml_policy(
            [
                {
                    "host": "127.0.0.1",
                    "rules": [{"schemes": ["http"], "methods": ["GET"]}],
                }
            ]
        )
        harness = self.spawn(initial)
        harness.write_policy(
            _yaml_policy([{"host": "127.0.0.1", "unsupported": True}])
        )
        harness.reload()
        event = harness.wait_for_event(
            lambda e: e.get("type") == "reload" and e.get("action") == "rejected"
        )
        self.assertIn("unsupported", event.get("error", "").lower())

        status, _ = harness.send_get(self.upstream_url)
        self.assertEqual(status, 200)
        status, _ = harness.send_request("POST", self.upstream_url)
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main()
