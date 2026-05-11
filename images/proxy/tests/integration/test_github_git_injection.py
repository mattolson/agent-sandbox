"""End-to-end GitHub Git smart-HTTP integration tests.

Drives the full pipeline from `services:` catalog shorthand through the real
`render-policy` module, into a running `mitmdump` proxy, into a recording fake
upstream. The catalog emits rules pinned to `github.com`; tests remap that host
onto the fake upstream's loopback address so the proxy never reaches real
GitHub.
"""

from __future__ import annotations

import unittest

import yaml

from .harness import (
    FakeUpstream,
    mitmdump_available,
    provision_secret_dir,
    remap_rendered_host,
    render_authored_policy,
    spawn_proxy,
)


def _skip_reason():
    return "mitmdump not available on PATH; install mitmproxy to run integration tests"


def _render_with_fake_upstream(source_text):
    """Render service-shorthand policy and rebind github.com onto loopback.

    Returns the rendered policy as YAML text suitable for `spawn_proxy`.
    """
    rendered = render_authored_policy(source_text)
    rebound = remap_rendered_host(rendered, {"github.com": "127.0.0.1"})
    return yaml.safe_dump(rebound, sort_keys=False)


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class GitHubGitInjectionTests(unittest.TestCase):
    def setUp(self):
        self.upstream = FakeUpstream()
        self.upstream.start()
        self.addCleanup(self.upstream.stop)

    def _spawn(self, source_text, *, secrets=None):
        rendered_text = _render_with_fake_upstream(source_text)
        env_overrides = {}
        if secrets:
            tempdir, secret_source = provision_secret_dir(secrets)
            self.addCleanup(tempdir.cleanup)
            env_overrides["AGENTBOX_SECRET_SOURCE"] = secret_source
        harness = spawn_proxy(rendered_text, env_overrides=env_overrides or None)
        self.addCleanup(harness.terminate)
        return harness

    def _upstream_url(self, path):
        return f"http://127.0.0.1:{self.upstream.port}{path}"

    def _expected_basic_authorization(self, secret_value):
        import base64

        token = base64.b64encode(f"x-access-token:{secret_value}".encode("ascii"))
        return f"Basic {token.decode('ascii')}"

    def test_private_read_with_auth_injects_authorization_on_upload_pack_rules(self):
        secret_value = "private-read-token-value"
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/private
    git:
      access: read
      auth:
        secret: github.agent-sandbox.read-token
""",
            secrets={"github.agent-sandbox.read-token": secret_value},
        )

        status, _ = harness.send_get(
            self._upstream_url(
                "/owner/private.git/info/refs?service=git-upload-pack"
            )
        )
        self.assertEqual(status, 200)
        status, _ = harness.send_request(
            "POST",
            self._upstream_url("/owner/private.git/git-upload-pack"),
            body=b"pack-data",
        )
        self.assertEqual(status, 200)

        requests = self.upstream.snapshot_requests()
        self.assertEqual(len(requests), 2)
        expected_auth = self._expected_basic_authorization(secret_value)
        for request in requests:
            self.assertEqual(
                request["headers"].get("Authorization"),
                expected_auth,
                f"missing or wrong Authorization on {request['method']} {request['path']}",
            )

        self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))

    def test_readwrite_injects_authorization_on_all_four_smart_http_rules(self):
        secret_value = "push-token-value"
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/push
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
""",
            secrets={"github.agent-sandbox.push-token": secret_value},
        )

        endpoints = [
            ("GET", "/owner/push.git/info/refs?service=git-upload-pack", b""),
            ("POST", "/owner/push.git/git-upload-pack", b"upload"),
            ("GET", "/owner/push.git/info/refs?service=git-receive-pack", b""),
            ("POST", "/owner/push.git/git-receive-pack", b"receive"),
        ]
        for method, path, body in endpoints:
            if method == "GET":
                status, _ = harness.send_get(self._upstream_url(path))
            else:
                status, _ = harness.send_request(
                    method, self._upstream_url(path), body=body
                )
            self.assertEqual(
                status, 200, f"unexpected status for {method} {path}: {status}"
            )

        requests = self.upstream.snapshot_requests()
        self.assertEqual(len(requests), 4)
        expected_auth = self._expected_basic_authorization(secret_value)
        for request in requests:
            self.assertEqual(
                request["headers"].get("Authorization"),
                expected_auth,
                f"missing or wrong Authorization on {request['method']} {request['path']}",
            )

        self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))

    def test_public_read_without_auth_emits_no_authorization(self):
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/public
    git:
      access: read
"""
        )

        status, _ = harness.send_get(
            self._upstream_url(
                "/owner/public.git/info/refs?service=git-upload-pack"
            )
        )
        self.assertEqual(status, 200)
        status, _ = harness.send_request(
            "POST",
            self._upstream_url("/owner/public.git/git-upload-pack"),
            body=b"pack",
        )
        self.assertEqual(status, 200)

        requests = self.upstream.snapshot_requests()
        self.assertEqual(len(requests), 2)
        for request in requests:
            self.assertNotIn("Authorization", request["headers"])

        for event in harness.snapshot_events():
            self.assertNotEqual(
                event.get("type"),
                "header_injection",
                f"public read should not emit header_injection events: {event}",
            )

    def test_public_read_does_not_allow_push_path(self):
        """A `git.access: read` entry must not authorize receive-pack rules."""
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/public
    git:
      access: read
"""
        )

        status, _ = harness.send_get(
            self._upstream_url(
                "/owner/public.git/info/refs?service=git-receive-pack"
            )
        )
        self.assertEqual(status, 403)
        status, _ = harness.send_request(
            "POST",
            self._upstream_url("/owner/public.git/git-receive-pack"),
            body=b"receive",
        )
        self.assertEqual(status, 403)
        self.assertEqual(self.upstream.snapshot_requests(), [])


if __name__ == "__main__":
    unittest.main()
