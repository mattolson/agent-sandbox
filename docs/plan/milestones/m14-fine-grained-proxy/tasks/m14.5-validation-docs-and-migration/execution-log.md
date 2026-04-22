# Execution Log: m14.5 - Validation, Docs, And Migration

## 2026-04-21 - Closed out PR-description follow-ups

Picked up the two minor follow-up items listed in the PR description. Both were things the m14.5 task log had
explicitly deferred to later policy-engine cleanup, but they were small enough to close out now and shrink the
test-only indirection:

- `06559d3` — enforcer now reads `AGENTBOX_RENDER_POLICY_PATH` from the environment (default unchanged). Dropped the
  `integration_addon.py` wrapper that existed solely to patch the module constant before `mitmdump` loaded the
  enforcer. Integration harness loads `enforcer.py` directly and sets the env var on the subprocess.
- `5a42805` — `render-policy`'s `fail()` now raises a typed `RenderPolicyError` instead of printing to stderr +
  `sys.exit(1)`. The enforcer's hot-reload path no longer needs `contextlib.redirect_stderr` + `SystemExit` catch —
  `RenderPolicyError` propagates through the normal `except Exception` path with its message intact. CLI `main()`
  catches the typed exception and prints/exits so shell users see identical behavior to before.

The second commit specifically retires the `redirect_stderr` workaround introduced during m14.5's integration-test
run. That workaround shipped because it solved the immediate user-facing problem, but it left `fail()` mixing a CLI
exit convention into a library path. Typed exception is the right shape.

## 2026-04-21 - Post-merge branch audit and cleanup

Ran a full audit of the m14 branch (commits `7cc027e..29eaa14`, 27 commits, 51 files, ~7.3k insertions) against the
milestone Definition of Done. DoD is substantively met, but the audit surfaced four fixable items that had drifted
out of m14.5's scope:

- **Templates and docs pointed users at `agentbox compose restart proxy`** even though m14.4 shipped SIGHUP hot
  reload. `docs/cli.md` was also missing an entry for the new `agentbox proxy reload` command.
- **`docs/policy/schema.md` preamble and `enforcer.py` header comment** still scoped the IR work to "m14.1"; accurate
  at the time of m14.1, misleading after m14.2's request-phase matcher shipped.
- **The `schemes` row in the enforcement-phase table** said "Request" only. Omits the CONNECT-time
  `https_not_permitted` rejection when a host's rules don't allow `https`.
- **`agentbox edit policy` still ran `compose restart proxy`** on save. With `agentbox proxy reload` available,
  restarting the container for a policy edit is unnecessary work.
- **CI ran `unittest discover -s images/proxy/tests` once.** Recursive discovery picks up
  `images/proxy/tests/integration/` only because that package has `__init__.py` — a subtle dependency that could
  silently drop the integration suite if the init file disappears.

Shipped as four separate commits on top of `29eaa14`:

- `59c6b1e` — template comments (`policy.yaml`, `user.agent.policy.yaml`) and `docs/cli.md` now reference
  `agentbox proxy reload`.
- `6379001` — dropped stale `m14.1` scope refs in the schema preamble and enforcer header; expanded the phase table
  so the `schemes` row captures both CONNECT and request enforcement.
- `f549233` — `agentbox edit policy` sends SIGHUP via `docker compose kill -s HUP proxy` instead of restarting the
  container. Updated the one test that asserted the restart call.
- `26e9147` — CI now has an explicit second step that runs discovery against
  `images/proxy/tests/integration/` directly. If subpackage discovery ever regresses, the second step fails loudly
  instead of silently skipping 7 tests.

**Left for the user:** `.agent-sandbox/policy/user.policy.yaml` drift from the updated template. Read-only for the
agent; the user will refresh on next local init/switch.

**Deferred:** a production-image smoke test for SIGHUP reload (would require a real image build in CI and a running
container — meaningful infra investment, not a cleanup).

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
