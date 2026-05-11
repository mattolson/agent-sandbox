# Execution Log: m15.7 - Integration And Boundary Tests

## 2026-05-10 - Implementation complete

Implemented all m15.7 scope in a single pass with no scope changes:

- Lifted `FakeUpstream` (was `_Upstream`) and the recording HTTP handler from
  `test_proxy_enforcement.py` into `images/proxy/tests/integration/harness.py`. Added
  `provision_secret_dir(secrets)` returning `(TemporaryDirectory, source_url)` with `0700`/`0600` permissions, and
  `render_authored_policy(source_text)` plus `remap_rendered_host(rendered, host_map)` so integration tests can drive
  the real `render-policy` module against `services:` shorthand and then rebind the catalog's `github.com` host onto
  loopback.
- Added `test_github_git_injection.py` covering private read with auth (2 upload-pack rules), readwrite (all 4
  smart-HTTP rules), public read without auth (no Authorization on upstream, no `header_injection` events), and a
  negative test that public read does not authorize receive-pack.
- Added `test_credential_shim_replace.py` covering the shimmed-replace path (fake `Authorization: Basic
  x-access-token:agentbox-proxy-managed` overwritten by the real `Authorization: Basic x-access-token:<secret>`) and
  the direct fail-closed path (proxy rejects with `header_injection_failed` / `existing_header_present` and never
  reaches the upstream).
- Each integration scenario asserts the deterministic secret value string is absent from every captured proxy stdout
  line via `self.assertNotIn(secret_value, "\n".join(harness.snapshot_lines()))`.
- Extended `test_render_policy.py` with `test_rendered_output_never_contains_resolved_secret_value` covering both a
  direct `domains[].transform` entry and a `git.auth.client_shim.kind: git-askpass` entry; asserts the resolved
  secret value never appears in rendered policy YAML, the `init.zsh` aggregate, or the `git-askpass/env.zsh` fragment.
- Extended `internal/scaffold/init_test.go` and `sync_test.go` with `assertNoProxySecretRuntime` calls on
  `sharedOverride`, `agentOverride`, and `modeFile` agent services (previously only the agent-specific layer was
  checked), and added `assertCredentialShimAgentReadOnly` walking every generated layer to fail-closed if any agent
  mount of `/run/agentbox/credential-shims` is not `:ro`.

**Issue:** `_load_render_policy_module` initially used the deprecated
`SourceFileLoader.load_module()` which works but spams DeprecationWarnings.

**Solution:** Switched to `importlib.util.spec_from_loader` + `module_from_spec` + `exec_module`, matching the pattern
already used in `test_render_policy.py::load_render_policy_module`.

**Decision:** Rebind `github.com` -> `127.0.0.1` on the rendered policy rather than altering the catalog. The catalog's
hard-coded host is a product contract for the user-facing `services:` shorthand; tests should not have a knob to
swap it. Rebinding preserves the rule paths, methods, query, and transform metadata - the parts under test - while
isolating the proxy from the real internet.

**Decision:** Drive every scenario through `services:` catalog shorthand instead of authoring `domains[].transform`
directly. m15.1 and m15.4 already cover the authored path; m15.7's value is in proving the full pipeline from user
intent through to upstream-visible headers.

**Decision:** Keep the rendered-output redaction test in `test_render_policy.py` rather than integration tests. The
renderer doesn't resolve secrets today, so the test is a structural guard against future regressions; running it
under `mitmdump` would add coverage that the integration scenarios already provide via `snapshot_lines()` checks.

**Verification:**
- `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` -> 163 tests, 0 failures
- `go test ./...` -> all packages pass

## 2026-05-10 - Initial task plan

Created the M15.7 task plan after reviewing the M15 milestone, m15.1 through m15.6 task plans, the existing proxy
integration harness at `images/proxy/tests/integration/harness.py`, the m15.4 header-injection integration tests in
`test_proxy_enforcement.py`, and the scaffold assertions added in m15.3 and m15.6.

**Decision:** Drive every GitHub Git scenario through `services:` shorthand rather than authored
`domains[].transform`. The catalog is the user-facing surface for the M15 GitHub flow, so end-to-end coverage should
exercise the catalog -> renderer -> matcher -> enforcer -> upstream path. Hand-authored `domains` transforms are
already covered by m15.1 and m15.4.

**Decision:** Use plain-HTTP fake upstreams via the existing harness `_Upstream` instead of attempting HTTPS. The
harness cannot complete a real TLS handshake, and the request-mutation pipeline is the boundary under test.
CONNECT-time inspection behavior is already covered by `test_proxy_enforcement.py`.

**Decision:** Keep the shimmed-replace assertion narrow to proxy mutation. The `agentbox-git-askpass.sh` runtime
behavior belongs in a separate base-image smoke test; m15.7 only asserts that a pre-set fake `Authorization` header is
replaced by the real proxy-injected value on shimmed rules.

**Decision:** Add explicit negative scaffold assertions on the agent service for the secret mount. m15.3 added a
positive assertion for the proxy side and a coarse `assertNoProxySecretRuntime`; m15.7 should pin the negative case
with bind, named-volume, and env-reference checks on both CLI and devcontainer layouts and on the sync/repair path.

**Decision:** Move the secret-redaction assertion into both an integration scope (proxy event lines) and a renderer
scope (rendered policy plus written shell fragments). The shell-fragment redaction is specific to m15.6 output; the
event-line redaction is a pipeline assertion that complements m15.4.

**Observation:** The existing harness already lets tests pass `env_overrides={"AGENTBOX_SECRET_SOURCE": ...}` and the
`_secret_source` helper writes secret files with `0600` permissions. Lifting that helper into `harness.py` keeps the
new integration files clean and matches the m15.4 pattern.

**Observation:** `git.access: read` with auth describes private read in plain English but the renderer does not name
it that way. The plan defers any renamed error or doc terminology to m15.8 and pins the existing behavior with tests
so the docs task can describe it accurately.
