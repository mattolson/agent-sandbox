# Task: m14.5 - Validation, Docs, And Migration

## Summary

Lock down the m14 behavior with automated coverage, migration guidance, and examples so later milestones build on a
stable policy surface.

## Scope

- Add tests for legacy domain-only fast path, request-aware allow and deny cases, service expansions, and hot reload
- Update `docs/policy/schema.md`, examples, and troubleshooting guidance for the richer rule model
- Document how domain-only behavior differs from request-phase behavior and when each applies
- Verify current agent images and template-generated baseline policies still work unchanged

## Acceptance Criteria

- [ ] Automated coverage exists for representative HTTP and HTTPS cases, including reload failure handling
- [ ] Docs show both legacy domain-only and new request-aware examples
- [ ] Users can tell whether a rule is enforced at CONNECT or request phase without reading proxy source
- [ ] Existing projects with domain-only policies continue to work unchanged

## Applicable Learnings

- `m14` is backward-compatible by design. Domain-only policies still render to the same CONNECT fast path; this is a
  feature-tour milestone more than a migration milestone. (from m14.1 plan)
- Unit-level coverage is already thick across matcher, catalog, enforcer, and reload (see m14.1–m14.4 task logs). The
  gap is wiring-level: no integration test exercises the full mitmproxy → addon → enforcement chain end to end.
- Security-sensitive policy rendering keeps one merge path. Tests should exercise the real `render-policy` module
  through `SourceFileLoader`, not a second normalization pipeline. (from m14.1)
- For proxy addons that block requests before `response` runs, decisions must be stored on the flow or response
  logging will relabel blocked requests as allowed. A regression test anchors this invariant. (from m14.2 learnings)
- Docs stale faster than code. The current `docs/policy/schema.md` still says "m14.1 does not yet ship request-phase
  enforcement," which contradicts the shipped behavior. Enforcement status sections must be re-checked at each task
  close.
- The m8 upgrade guide (`docs/upgrades/m8-layered-layout.md`) is the migration-doc precedent in this repo. Use its
  shape as a template when writing the m14 upgrade note.

## Plan

### Files Involved

**Docs**

- `docs/policy/schema.md` — fix stale "Enforcement Status" section; add a "CONNECT vs request-phase enforcement"
  explainer that tells users which phase blocks each rule; link to new examples
- `docs/policy/examples/request-rules.yaml` — **new** minimal rich-rules example (methods + path prefix + query
  exact) that complements the existing `github-repos.yaml`
- `docs/policy/examples/layered-merge.yaml` — **new** two-layer example showing additive merge vs `merge_mode: replace`
  at the host layer, since nothing in `examples/` currently demonstrates this
- `docs/upgrades/m14-request-aware-rules.md` — **new** "what's new in m14" note rather than a destructive migration
  guide. Covers: (1) your policies still work as-is, (2) here are the new authoring surfaces, (3) how to tell which
  phase enforces each rule, (4) how to hot-reload
- `docs/troubleshooting.md` — add entries for "policy rejected with schema error" and "request blocked unexpectedly"
  (how to read the JSON decision log, how to distinguish CONNECT-phase from request-phase blocks)

**Tests**

- `images/proxy/tests/integration/` — **new** integration test harness. A pytest fixture spawns `mitmdump -s
  enforcer.py` on an ephemeral port against a throwaway policy file, proxies requests through it with `httpx`, and
  asserts on status codes + captured stdout JSON log lines. Covers:
  - Host-only allow and block at CONNECT
  - Method-restricted host (GET allowed, POST blocked)
  - Path-prefix restriction (in-prefix allowed, out-of-prefix blocked)
  - Query-exact restriction (matching allowed, mismatched blocked)
  - SIGHUP reload swap (edit policy, send SIGHUP, observe new decision)
  - SIGHUP rejection (bad policy keeps old matcher)
- `images/proxy/tests/test_render_policy.py` — strengthen the existing `test_single_file_legacy_inputs_render_to_
  canonical_host_records` into an explicit "baseline services render unchanged" regression: snapshot each agent's
  baseline IR (claude, codex, gemini, opencode, copilot, factory, pi) and assert stability.
- `.github/workflows/proxy-tests.yml` — add the integration suite to the existing proxy-tests workflow so CI exercises
  it.

**Templates (light touch)**

- `internal/embeddata/templates/user.policy.yaml` — add a commented-out rich-rule example pointing at the schema doc,
  so users discover the capability when they first edit their policy. Do not change the active content.

### Approach

Split the work into three threads that can interleave:

1. **Fix stale docs first.** The Enforcement Status section in `schema.md` actively misinforms. Touch that before
   anything else so the rest of the docs work builds on a correct baseline. Add the CONNECT-vs-request-phase
   explainer at the same time; it's the single most-requested clarification implied by the milestone definition of
   done.

2. **Write the "what's new" upgrade note.** Frame it as feature-tour + compatibility guarantees, not a destructive
   migration. Follow the m8 upgrade doc's structure but trim the "rename these files" scaffolding — no files need
   renaming for m14. Cross-link to the new examples.

3. **Build the integration harness and then write focused tests.** The harness is the investment; each scenario is
   cheap to add after that. Use `mitmdump` as a subprocess because it gives us a real event loop, real signal
   handlers, and real JSON logs without a Docker dependency. Target ~7 scenarios total — enough to catch wiring
   regressions, few enough to stay fast.

   Keep the suite fast-path-friendly: share one proxy process per test class where possible, use `httpx` with the
   proxy URL, and capture stdout via subprocess pipes. Assert on both HTTP status and the structured decision log
   line.

4. **Snapshot baseline IR.** Extend the existing render-policy test to iterate every agent catalog entry, render its
   baseline-only policy (`services: [<agent>]`), and assert the rendered IR matches an inline expected structure.
   Keeps backward compatibility explicit rather than implicit.

5. **Close with example files and the template nudge.** Once the docs are corrected and the explainer exists, adding
   `request-rules.yaml` and `layered-merge.yaml` is mostly a copy-paste exercise. Finish by adding the commented
   hint to `user.policy.yaml`.

### Implementation Steps

- [x] Fix `docs/policy/schema.md` "Enforcement Status" section to reflect m14.2–m14.4 shipped behavior
- [x] Add "CONNECT vs request-phase enforcement" subsection to `docs/policy/schema.md` with a small table mapping
      rule fields to the phase that enforces them
- [x] Write `docs/upgrades/m14-request-aware-rules.md` as a what's-new note with backward-compatibility guarantee,
      authoring surface tour, enforcement-phase map, and reload workflow
- [x] Add `docs/policy/examples/request-rules.yaml` (methods + path prefix + query exact, minimum viable example)
- [x] Add `docs/policy/examples/layered-merge.yaml` (two-layer additive + `merge_mode: replace`)
- [x] Add troubleshooting entries: "policy rejected with schema error" and "request blocked unexpectedly"
- [x] Extend `test_render_policy.py` with a baseline-IR snapshot test covering every agent catalog entry
- [x] Scaffold `images/proxy/tests/integration/` with a unittest-compatible harness that spawns `mitmdump -s
      integration_addon.py` and exposes a proxy URL + captured JSON log lines
- [x] Add integration scenarios: CONNECT allow, CONNECT block, method restriction, path prefix, query exact, SIGHUP
      reload swap, SIGHUP rejection with last-known-good
- [x] Wire the integration suite into `.github/workflows/proxy-tests.yml`
- [x] Add commented rich-rule example to `internal/embeddata/templates/user.policy.yaml`
- [x] Run `go test ./...` and the full proxy test suite (unit + integration); confirm green

### Open Questions

All four resolved with the drafted defaults on 2026-04-19:

1. **Integration harness.** Build a mitmdump-subprocess pytest fixture now, ~7 scenarios. Fall back to Docker-based
   CI-only integration if the subprocess pattern proves flaky.
2. **Upgrade doc.** Separate `docs/upgrades/m14-request-aware-rules.md`, framed as a what's-new note with an
   explicit backward-compatibility guarantee.
3. **Template scaffold hint.** Commented rich-rule example in `user.policy.yaml` for discoverability. Active content
   unchanged.
4. **Baseline IR snapshot.** Inline expected structures in `test_render_policy.py`. Golden files would drift
   silently; inline forces reviewers to eyeball catalog changes.

## Outcome

### Acceptance Verification

- [x] **Automated coverage exists for representative HTTP and HTTPS cases, including reload failure handling.**
      7 integration scenarios under `images/proxy/tests/integration/`: CONNECT allow, CONNECT block, method
      restriction, path prefix, query exact, SIGHUP reload swap, SIGHUP rejection with last-known-good. Each asserts
      both HTTP status and the structured decision log line.
- [x] **Docs show both legacy domain-only and new request-aware examples.** `examples/all-agents.yaml` (services
      union) and `examples/github-repos.yaml` remain; new `examples/request-rules.yaml` demonstrates methods, path
      prefix, and query exact; new `examples/layered-merge.yaml` demonstrates additive and `merge_mode: replace`
      across two layers.
- [x] **Users can tell whether a rule is enforced at CONNECT or request phase without reading proxy source.**
      `docs/policy/schema.md` has a new "Enforcement Phases" table mapping rule fields to their enforcement phase;
      `docs/upgrades/m14-request-aware-rules.md` repeats the guidance in prose with a practical example.
- [x] **Existing projects with domain-only policies continue to work unchanged.** New
      `BaselinePolicyRegressionTests` in `test_render_policy.py` snapshots every agent's baseline render (claude,
      codex, factory, gemini, opencode, pi, copilot) and asserts the catch-all rule shape is stable.

### Learnings

- **Integration tests surface bugs unit tests miss.** The first integration run exposed a real reload bug:
  render-policy's `fail()` calls `sys.exit(1)`, which `except Exception` didn't catch — the SIGHUP handler crashed
  silently with only a raw stderr line and no structured `rejected` event. Unit-level coverage missed this because
  every unit test injected `reload_renderer` (a plain Python callable that raises PolicyError). Fix: wrap the
  production renderer in `contextlib.redirect_stderr` + `SystemExit` catch, so bad reloads emit the real error
  message in the structured event.
- **urllib's `no_proxy` is silently sticky.** An explicit `ProxyHandler({"http": proxy})` still bypasses the proxy
  for loopback targets because urllib consults `proxy_bypass()`. Using a raw socket + absolute-form request line is
  the reliable way to guarantee traffic hits the proxy.
- **The initial-load path and the reload path have different strictness.** `PolicyMatcher.from_policy_path` requires
  `query.exact.<name>` to be a list; `render-policy` accepts a bare string and promotes it. Integration tests that
  write policy files directly must use the matcher's stricter form.
- **Addon constants need an override hook.** `RENDER_POLICY_PATH` is hard-coded at `/usr/local/bin/render-policy`,
  so integration tests would fail outside a built image. The wrapper-addon pattern (`-s integration_addon.py` that
  imports enforcer and patches the constant) keeps the override test-local without touching the production default.

### Follow-up Items

- **Done (2026-04-21, `06559d3`): env-var override for `RENDER_POLICY_PATH` in `enforcer.py`.** Integration tests no
  longer need the wrapper addon; harness loads `enforcer.py` directly and sets `AGENTBOX_RENDER_POLICY_PATH` on the
  subprocess.
- **Done (2026-04-21, `5a42805`): `RenderPolicyError` typed exception from `render-policy`.** `fail()` raises the
  typed exception and the enforcer's hot-reload path catches it directly. `contextlib.redirect_stderr` +
  `SystemExit` workaround removed. CLI main() still prints to stderr and exits 1, so shell users see identical
  behavior.
