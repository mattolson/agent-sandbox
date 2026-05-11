# Execution Log: m15.7 - Integration And Boundary Tests

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
