# Execution Log: m14.5 - Validation, Docs, And Migration

## 2026-04-19 16:10 UTC - Task complete

All 11 implementation steps done. Full suite green: `go test ./...` (Go) and 79 proxy Python tests (72 unit + 7
integration). The integration harness spawns real `mitmdump` with `integration_addon.py` that patches
`RENDER_POLICY_PATH` at import so the addon points at this repo's `render-policy` rather than `/usr/local/bin/`.

**Issue uncovered during integration:** a bad SIGHUP reload crashed silently. Root cause: `render-policy`'s
`fail()` calls `sys.exit(1)`, which raises `SystemExit` — not caught by `except Exception` in `PolicyEnforcer.reload()`.
**Solution:** wrap the production renderer in `contextlib.redirect_stderr(io.StringIO())` + explicit `SystemExit`
catch inside `_render_matcher`, convert to `RuntimeError` with the captured stderr as message. The rejected-reload
event now carries the real error text (e.g., "domains[0] contains unsupported keys: ['unsupported']") rather
than a generic "exited with code 1".

**Issue uncovered:** urllib ProxyHandler silently bypasses the proxy for loopback targets because of
`proxy_bypass()`. **Solution:** raw-socket HTTP/1.1 client in the harness using absolute-form request URIs so
traffic can only reach the upstream through the proxy.

**Scope creep avoided:** the code-reuse reviewer suggested rewriting `render-policy`'s `fail()` to raise a typed
exception and refactoring enforcer's error handling accordingly. Noted in follow-ups for a future policy-engine
cleanup — the current in-place fix delivers the right user-facing behavior with a smaller change.

**Simplify pass applied:** encapsulated ProxyHarness lifecycle (removed `_workdir` / `_reader_thread` post-construction
mutation), collapsed 7 tests' `try/finally + terminate_proxy` duplication into a `_ProxyTestCase` base class with
`addCleanup`, replaced the hand-rolled URL split with `urllib.parse.urlsplit`, tightened `send_request` to raise
`HarnessTimeoutError` rather than silently returning status 0 on socket timeout, and named the harness's wait
failures as a dedicated exception instead of `AssertionError`.

## 2026-04-19 15:30 UTC - Closed the open questions, moving to execution

All four open questions resolved with the drafted defaults:

- Build the mitmdump-subprocess integration harness now.
- Ship a separate `docs/upgrades/m14-request-aware-rules.md` as a what's-new note.
- Add a commented rich-rule example to `user.policy.yaml` for discoverability.
- Inline baseline-IR snapshots in `test_render_policy.py` instead of golden files.

## 2026-04-19 - Drafted the task plan

Reviewed the m14 milestone plan, all four prior task outcomes, and the current state of the repo (tests, docs,
templates, catalog baselines). The code side of m14 is effectively done — unit coverage is thick across matcher,
catalog, enforcer, and reload. The gaps are docs drift, missing examples, no integration wiring coverage, and no
"what's new" note for users coming from earlier milestones.

**Observation:** `docs/policy/schema.md` still says "m14.1 does not yet ship request-phase enforcement for methods,
path, or query." That contradicts the shipped behavior after m14.2. Fixing this is the single highest-leverage doc
change in the task.

**Observation:** `docs/policy/examples/` only has `all-agents.yaml` (a plain union of string services) and
`github-repos.yaml` (a focused repo-scoped example). Nothing demonstrates rich rules with methods/path/query
directly, and nothing demonstrates host-layer `merge_mode: replace`.

**Observation:** No integration harness exists — all proxy tests are unit-level against fake flows. The milestone
risk explicitly endorses "a smaller set of proxy integration tests for wiring," so building a minimal pytest fixture
that spawns `mitmdump -s enforcer.py` is the right investment.

**Decision:** Frame the upgrade doc as "what's new in m14" rather than a destructive migration guide. m14 is
backward-compatible by design; calling it a migration would mislead users into looking for breaking changes that
don't exist.

**Decision:** Snapshot the rendered IR for each agent's baseline service expansion inline in the existing
`test_render_policy.py` rather than using golden files. Inline structures force a reviewer to eyeball catalog
changes; golden files would drift silently.

**Flagged four open questions** — all with drafted defaults — covering integration-harness investment, separate
upgrade doc vs inline, template scaffold hints, and snapshot shape.
