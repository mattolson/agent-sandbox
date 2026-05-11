"""End-to-end credential-shim integration tests.

Covers the two `on_existing_header` behaviors that distinguish a shimmed
GitHub Git auth path from a direct one:

- `git.auth.client_shim.kind: git-askpass` renders `on_existing_header:
  replace`, so a fake `Authorization` header set by the agent-side askpass
  setup gets overwritten with the proxy-injected real credential before
  reaching the upstream.
- Direct `git.auth.secret` without `client_shim` keeps `on_existing_header:
  fail`, so any pre-existing `Authorization` header on a matched request
  blocks the request closed rather than silently being replaced.
"""

from __future__ import annotations

import base64
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
    rendered = render_authored_policy(source_text)
    rebound = remap_rendered_host(rendered, {"github.com": "127.0.0.1"})
    return yaml.safe_dump(rebound, sort_keys=False)


def _basic_authorization(username, secret):
    token = base64.b64encode(f"{username}:{secret}".encode("ascii"))
    return f"Basic {token.decode('ascii')}"


@unittest.skipUnless(mitmdump_available(), _skip_reason())
class CredentialShimReplaceTests(unittest.TestCase):
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

    def test_client_shim_replaces_fake_authorization_with_real_secret(self):
        """A shimmed rule replaces a client-supplied fake Authorization."""
        secret_value = "shim-real-secret-value"
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/shim
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
        client_shim:
          kind: git-askpass
""",
            secrets={"github.agent-sandbox.push-token": secret_value},
        )

        fake_auth = _basic_authorization("x-access-token", "agentbox-proxy-managed")
        status, _ = harness.send_request(
            "POST",
            self._upstream_url("/owner/shim.git/git-receive-pack"),
            body=b"push-data",
            headers={"Authorization": fake_auth},
        )
        self.assertEqual(status, 200)

        requests = self.upstream.snapshot_requests()
        self.assertEqual(len(requests), 1)
        upstream_auth = requests[0]["headers"].get("Authorization")
        self.assertEqual(
            upstream_auth,
            _basic_authorization("x-access-token", secret_value),
        )
        self.assertNotEqual(upstream_auth, fake_auth)
        self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))

    def test_direct_injection_fails_closed_when_authorization_already_present(self):
        """Without a client_shim, a pre-set Authorization is fail-closed."""
        secret_value = "direct-secret-value"
        harness = self._spawn(
            """
services:
  - name: github
    repos:
      - owner/direct
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.direct-token
""",
            secrets={"github.agent-sandbox.direct-token": secret_value},
        )

        status, _ = harness.send_request(
            "POST",
            self._upstream_url("/owner/direct.git/git-receive-pack"),
            body=b"push-data",
            headers={"Authorization": "Bearer client-supplied"},
        )
        self.assertEqual(status, 403)
        self.assertEqual(self.upstream.snapshot_requests(), [])

        event = harness.wait_for_event(
            lambda e: e.get("phase") == "request"
            and e.get("reason") == "header_injection_failed"
        )
        self.assertEqual(event.get("detail"), "existing_header_present")
        self.assertEqual(event.get("secret"), "github.agent-sandbox.direct-token")
        self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))


if __name__ == "__main__":
    unittest.main()
