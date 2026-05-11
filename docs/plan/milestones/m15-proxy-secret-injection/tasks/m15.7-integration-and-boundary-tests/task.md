# Task: m15.7 - Integration And Boundary Tests

## Summary

Add end-to-end coverage that drives the real proxy through the M15 secret-injection pipeline for GitHub Git smart HTTP,
plus mount-layout boundary tests proving the agent container cannot reach proxy-only secret material under the generated
CLI and devcontainer compose layouts.

## Scope

- Drive a fake upstream with the existing mitmdump-based integration harness through repo-scoped GitHub Git rules
  rendered from service-catalog shorthand
- Cover `git.access: read` with auth (private clone/fetch), `git.access: readwrite` (push), and `git.access: read`
  without auth (public clone/fetch)
- Prove `upload-pack` discovery and pack-transfer requests both receive the injected `Authorization` header for a
  read-with-auth entry
- Prove `receive-pack` discovery and pack-transfer requests receive the injected `Authorization` header for a readwrite
  entry
- Prove unauthenticated `git.access: read` emits no injection metadata and that matching requests reach the upstream
  without an `Authorization` header
- Cover the `git.auth.client_shim.kind: git-askpass` end-to-end path: fake `Authorization` set by the agent-side
  askpass setup gets replaced by the real proxy-injected value before reaching the fake upstream
- Add scaffold/runtime tests proving the agent service has no bind mount and no read access to
  `/run/secrets/agentbox` under generated CLI and devcontainer compose layouts, and proving the agent retains read-only
  access to `/run/agentbox/credential-shims`
- Add boundary tests proving the generated `credential_shim` rendered output, the written `init.zsh` aggregate, and
  the `git-askpass/env.zsh` fragment never contain resolved secret values
- Exclude live GitHub requests, the GitHub REST surface, request-body or response-body assertions beyond status
  codes, and any new policy schema or catalog behavior

## Acceptance Criteria

- [x] Integration test proves private upload-pack discovery (`/owner/repo.git/info/refs?service=git-upload-pack`) and
      pack transfer (`/owner/repo.git/git-upload-pack`) reach the fake upstream with `Authorization: Basic ...`
      derived from the file-backed secret
- [x] Integration test proves push discovery (`/owner/repo.git/info/refs?service=git-receive-pack`) and pack transfer
      (`/owner/repo.git/git-receive-pack`) reach the fake upstream with `Authorization: Basic ...`
- [x] Integration test proves public `git.access: read` without `git.auth` emits no `transform` metadata and that
      matching upload-pack requests reach the fake upstream without `Authorization`
- [x] Integration test proves a request that pre-sends a fake `Authorization` header for the shimmed flow gets that
      header replaced (not failed) and the upstream sees the real proxy-injected value
- [x] Integration test proves a request that pre-sends an `Authorization` header for a direct (non-shim) injection rule
      is failed closed by the proxy and never reaches the upstream
- [x] Integration test asserts proxy logs and emitted events contain the secret ID and redacted markers only — no
      file-backed secret value appears in any captured event line
- [x] Scaffold test proves generated CLI and devcontainer base compose layers mount `/run/secrets/agentbox` into
      `proxy` only and that `agent` has no bind, named-volume, or env reference to the host secret path
- [x] Scaffold test proves generated CLI and devcontainer base compose layers mount
      `proxy-credential-shims:/run/agentbox/credential-shims` read-only into `agent` and read/write into `proxy`
- [x] Renderer test proves a `git.auth.client_shim.kind: git-askpass` entry produces a rendered `credential_shim`
      block, an `init.zsh` aggregate, and a `git-askpass/env.zsh` fragment that contain only fake values and logical
      secret IDs, never the resolved secret
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] `go test ./...`

## Applicable Learnings

- Thick unit coverage does not substitute for integration wiring coverage; a real `mitmdump` integration test catches
  failure modes (SystemExit on stderr, signal handler scope, urllib `no_proxy` bypass) that mocked unit tests miss.
- urllib `ProxyHandler` honors `no_proxy` and silently bypasses the proxy for loopback targets. The integration harness
  must keep using its raw-socket request path; do not switch to `requests`/`urllib` for these tests.
- mitmproxy `Request.path` includes the query string, so upload-pack vs receive-pack assertions should compare path and
  query separately or compare against full request lines, not pre-split `path` fields.
- HTTPS rules with transforms force request inspection at CONNECT, so any HTTPS-shaped integration assertion must
  account for the harness limitation that it does not complete a real TLS handshake. Prefer HTTP-scheme integration
  fixtures unless a CONNECT-only boundary is the point of the test.
- File-backed secret readers reject symlinks and non-regular files, so the integration harness must materialize secret
  files as plain regular files with mode `0600` under a `0700` directory, owned by the test user.
- Rendered `credential_shim` and the written shell fragments are renderer-owned. Authored top-level `credential_shim`
  must remain rejected; tests that drive shim output should drive it through `git.auth.client_shim`, not by editing the
  rendered IR.
- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs.
- Regression tests over `docker compose config` style output should assert semantic invariants (no mount target X on
  service Y) rather than locking a specific YAML shape.

## Plan

### Files Involved

- `images/proxy/tests/integration/harness.py` - small additions if needed: a fake upstream that captures
  `Authorization`, a helper to provision a temporary `0700` secret directory with `0600` secret files, and a way to
  pass `AGENTBOX_SECRET_SOURCE` plus `AGENTBOX_CREDENTIAL_SHIM_INIT_PATH` through `spawn_proxy`
- `images/proxy/tests/integration/test_github_git_injection.py` - new file: end-to-end GitHub Git read, readwrite, and
  public-read scenarios driven through service-catalog shorthand, plus the redacted-log assertion
- `images/proxy/tests/integration/test_credential_shim_replace.py` - new file: end-to-end coverage for the shimmed
  `Authorization` replacement path and the direct-injection `fail` path
- `images/proxy/tests/test_render_policy.py` - extend with a redaction boundary test that asserts no resolved secret
  value appears in rendered policy output, the `init.zsh` aggregate, or the `git-askpass/env.zsh` fragment when the
  secret source is provisioned
- `internal/scaffold/init_test.go` - extend the existing CLI and devcontainer assertions with explicit negative
  assertions on the agent service: no `/run/secrets/agentbox` mount, no host secret-directory bind, and no
  `AGENTBOX_SECRET_SOURCE` env reference
- `internal/scaffold/sync_test.go` - mirror the negative agent-mount assertion for the sync/repair path so older
  managed base layers cannot regress into exposing the secret mount to the agent
- `docs/plan/learnings.md` - append any genuinely new learnings discovered while wiring integration coverage

### Approach

Drive every scenario through service-catalog shorthand, not through hand-authored `domains[].transform`. The catalog is
the user-facing surface for M15's GitHub flow, so the integration tests should pin the full pipeline from
`services:` shorthand all the way through rendered policy, matched request, secret resolution, transform application,
and upstream-visible header. Hand-authored `domains` paths are already covered by M15.1, M15.4, and the existing
`test_proxy_enforcement.py::test_header_injection_reaches_upstream_for_matched_rule`.

Use HTTP (not HTTPS) fake upstream URLs for these tests. The existing harness uses a plain-HTTP `_Upstream`, and that
keeps the test surface focused on the request-mutation pipeline. Pick deterministic per-test owner/repo names so the
service catalog emits the exact rule shapes the test expects, and authorize the fake upstream's host with an explicit
`domains:` allow entry alongside the `services:` shorthand so the proxy lets the request through to the upstream.

For each scenario:

- Read with auth: render
  ```yaml
  services:
    - name: github
      repos:
        - owner/private
      git:
        access: read
        auth:
          secret: github.agent-sandbox.read-token
  ```
  and assert both `info/refs?service=git-upload-pack` and `git-upload-pack` requests reach the upstream with
  `Authorization: Basic base64("x-access-token:<secret>")`.

- Readwrite: render
  ```yaml
  services:
    - name: github
      repos:
        - owner/push
      git:
        access: readwrite
        auth:
          secret: github.agent-sandbox.push-token
  ```
  and assert all four rules (`info/refs?service=git-upload-pack`, `git-upload-pack`,
  `info/refs?service=git-receive-pack`, `git-receive-pack`) reach the upstream with the injected header.

- Public read without auth: render
  ```yaml
  services:
    - name: github
      repos:
        - owner/public
      git:
        access: read
  ```
  and assert `info/refs?service=git-upload-pack` reaches the upstream with no `Authorization` header and that the
  rendered policy contains no `transform` metadata on those rules.

- Shimmed replace: render
  ```yaml
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
  ```
  Send the request with a fake `Authorization: Basic <fake>` header and assert the upstream sees `Authorization: Basic
  base64("x-access-token:<real-secret>")`, not the fake.

- Direct fail-closed: render the readwrite shape without `client_shim` and send the same fake header. Assert the proxy
  rejects the request before the upstream sees it.

The fake upstream that already lives in `test_proxy_enforcement.py` captures requests in a thread-safe list; lift it into
`harness.py` so both integration test files can reuse it without duplication. Add a small helper that materializes a
temporary secret directory and writes secret values with `0600` permissions, similar to the existing
`_secret_source` helper in `IntegrationHeaderInjectionTests`.

For the scaffold boundary tests, extend the existing `assertProxySecretRuntime` / `assertNoProxySecretRuntime` helpers
with explicit checks that the agent service has no bind, named volume, or environment reference to
`/run/secrets/agentbox` or to the host secret directory expansion. Mirror the same negative assertion in
`internal/scaffold/sync_test.go` so a sync-repair pass cannot reintroduce the mount on `agent`. The credential-shim
volume's read-only `agent` mount is already covered by `assertCredentialShimRuntime`; extend that helper with an
explicit assertion that the agent's compose entry uses the `:ro` mode and that no other compose layer overrides it
back to read/write.

For the redaction boundary test in `test_render_policy.py`, render a policy that includes both a direct
`domains[].transform.request.headers` entry and a `git.auth.client_shim.kind: git-askpass` shorthand, point the
renderer at a temporary file-backed secret source with a deterministic value, and assert that value does not appear
anywhere in: the rendered policy text, the `credential_shim` block, the written `init.zsh` aggregate, or the
`git-askpass/env.zsh` fragment. This is a renderer-level test, not an integration test; it should run without
`mitmdump`.

Keep the proxy log redaction assertion narrow: the integration tests should call `harness.snapshot_lines()` and
`harness.snapshot_events()` and assert the deterministic secret value string is absent from every captured line. Do not
inspect the structure of audit events beyond "the secret ID is present and the secret value is absent."

Skip every integration test cleanly with `unittest.skipUnless(mitmdump_available(), ...)`, matching the existing
harness pattern. This task should not introduce a CI dependency that breaks environments without `mitmdump`.

### Implementation Steps

- [x] Lift the `_Upstream` fake server out of `test_proxy_enforcement.py` into a shared `FakeUpstream` helper in
      `harness.py`
- [x] Add a `provision_secret_dir(secrets)` helper to `harness.py` that returns a `(TemporaryDirectory, source_url)`
      tuple with the file backend rooted at a `0700` temp directory containing `0600` secret files
- [x] Add `render_authored_policy` plus `remap_rendered_host` helpers so integration tests can drive `services:`
      shorthand through the real `render-policy` module and rebind the catalog's `github.com` host onto loopback
- [x] Add `test_github_git_injection.py` with private-read-with-auth, readwrite, and public-read scenarios plus a
      negative check that public-read does not authorize receive-pack
- [x] Add `test_credential_shim_replace.py` with the shimmed replace and direct fail-closed scenarios
- [x] Extend `test_render_policy.py` with the rendered-output and shell-fragment redaction boundary test
- [x] Extend `internal/scaffold/init_test.go` agent-service negative assertions and add
      `assertCredentialShimAgentReadOnly` walking all generated layers
- [x] Extend `internal/scaffold/sync_test.go` to mirror the same negative assertions on the repair paths
- [x] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] Run `go test ./...`

### Open Questions

- Should the shimmed replace test also drive the askpass helper from `images/base/agentbox-git-askpass.sh` as a real
  subprocess to prove the askpass returns the documented placeholders? Recommended default: no — that crosses into
  base-image runtime territory that belongs in a separate base-image smoke test. Keep the integration test focused on
  proxy mutation behavior and assert the askpass script's content separately with a static unit-level check if needed.
- Should we add an HTTPS-shaped CONNECT-time injection test? Recommended default: no for m15.7 — the harness cannot
  complete a real TLS handshake and the existing CONNECT-time inspection behavior is already covered by
  `test_proxy_enforcement.py`. Re-evaluate if M15.8 docs or M16 work needs the HTTPS upstream surface.
- Should `git.access: read` with auth be reclassified as "private read" in the docs and renderer error messages?
  Recommended default: leave the renderer alone; this is an M15.8 docs concern. M15.7 should pin the behavior with
  tests so the docs task can describe it accurately.

## Outcome

### Acceptance Verification

- [x] Private read with auth covered by
      `images/proxy/tests/integration/test_github_git_injection.py::GitHubGitInjectionTests::test_private_read_with_auth_injects_authorization_on_upload_pack_rules`
- [x] Readwrite covered by
      `test_github_git_injection.py::GitHubGitInjectionTests::test_readwrite_injects_authorization_on_all_four_smart_http_rules`
- [x] Public read without auth covered by
      `test_github_git_injection.py::GitHubGitInjectionTests::test_public_read_without_auth_emits_no_authorization`
      and
      `test_public_read_does_not_allow_push_path`
- [x] Shim replace covered by
      `images/proxy/tests/integration/test_credential_shim_replace.py::CredentialShimReplaceTests::test_client_shim_replaces_fake_authorization_with_real_secret`
- [x] Direct fail-closed covered by
      `test_credential_shim_replace.py::CredentialShimReplaceTests::test_direct_injection_fails_closed_when_authorization_already_present`
- [x] Log-line redaction asserted inline in each integration scenario via
      `self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))`
- [x] Secret mount negative assertions covered by `assertNoProxySecretRuntime` calls on every generated layer
      (`base`, `agent`, `sharedOverride`, `agentOverride`, `modeFile`) in `internal/scaffold/init_test.go` and
      `internal/scaffold/sync_test.go`
- [x] Credential-shim volume read-only assertion covered by `assertCredentialShimAgentReadOnly` in both scaffold
      test files
- [x] Rendered-output and shell-fragment redaction covered by
      `images/proxy/tests/test_render_policy.py::RenderPolicyTests::test_rendered_output_never_contains_resolved_secret_value`
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` — 163 tests pass
- [x] `go test ./...` — all packages pass

### Learnings

- The mitmproxy enforcer matches the URL host but forwards to the upstream named in that URL. Integration tests for
  catalog rules that hard-code real hostnames (e.g. `github.com`) must either own DNS or rebind the rendered host
  onto loopback. Rebinding through `remap_rendered_host` keeps the catalog's path, method, query, and transform
  shapes intact while isolating the test from the real internet.
- Loading `render-policy` as a Python module from a non-`.py` filename requires `SourceFileLoader` plus
  `importlib.util.spec_from_loader` and `exec_module`; the deprecated `loader.load_module()` still works but the
  modern form matches `test_render_policy.py` and avoids deprecation noise.
- The renderer never reads resolved secret values today, so the rendered-output redaction test passes trivially. It
  is still worth keeping as a defense-in-depth guard against a future refactor that resolves secrets at render time
  or accidentally embeds values into shell fragments.

### Follow-up Items

- `m15.8` should reference the integration scenarios pinned here as the canonical examples for read, readwrite,
  public-read, and shimmed-replace flows. The `git.access: read` plus `git.auth` case should be documented as
  "private read" terminology since the catalog does not distinguish that case in error messages today.
- A future task should add a base-image smoke test that exercises `agentbox-git-askpass.sh` end-to-end inside a
  container; m15.7 keeps base-image runtime out of scope.
- Consider lifting `assertCredentialShimAgentReadOnly` and `assertNoProxySecretRuntime` into a small helper file so
  future per-mount boundary tests can share them across init/sync test files without further duplication.
