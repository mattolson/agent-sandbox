"""End-to-end integration tests that drive the real mitmdump process.

Each test spawns a fresh proxy with a crafted policy file, then sends real HTTP
requests (or raw CONNECT probes) through it and asserts on both the HTTP
response and the structured decision log emitted to stdout.

The suite is skipped when `mitmdump` is not on PATH, so the plain unit-test
discover run still works in minimal environments. CI installs `mitmproxy` to
pull it in.
"""

from __future__ import annotations

import http.server
import threading
import unittest

import yaml

from .harness import mitmdump_available, spawn_proxy


def _yaml_policy(domains):
    return yaml.safe_dump({"domains": domains}, sort_keys=False)


def _skip_reason():
    return "mitmdump not available on PATH; install mitmproxy to run integration tests"


class _RecordingHTTPServer(http.server.ThreadingHTTPServer):
    def __init__(self, server_address, handler_class):
        super().__init__(server_address, handler_class)
        self._requests = []
        self._requests_lock = threading.Lock()

    def record_request(self, method, path, body):
        with self._requests_lock:
            self._requests.append((method, path, body))

    def snapshot_requests(self):
        with self._requests_lock:
            return list(self._requests)


class _UpstreamHandler(http.server.BaseHTTPRequestHandler):
    def _respond(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else b""
        self.server.record_request(self.command, self.path, body)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler convention
        self._respond()

    def do_POST(self):  # noqa: N802
        self._respond()

    def log_message(self, format, *args):  # noqa: A002 - silence default logging
        return


class _Upstream:
    def __init__(self):
        self.server = _RecordingHTTPServer(("127.0.0.1", 0), _UpstreamHandler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2.0)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.port}/"

    def snapshot_requests(self):
        return self.server.snapshot_requests()


class _ProxyTestCase(unittest.TestCase):
    def spawn(self, policy_text, **kwargs):
        harness = spawn_proxy(policy_text, **kwargs)
        self.addCleanup(harness.terminate)
        return harness

    def upstream(self):
        upstream = _Upstream()
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

    def test_method_restriction_blocks_streamed_post_body_before_upstream(self):
        harness = self.spawn(
            self._policy({"methods": ["GET"]}),
            mitmdump_settings=("stream_large_bodies=1",),
        )
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
