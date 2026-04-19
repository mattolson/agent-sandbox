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

- [ ] Fix `docs/policy/schema.md` "Enforcement Status" section to reflect m14.2–m14.4 shipped behavior
- [ ] Add "CONNECT vs request-phase enforcement" subsection to `docs/policy/schema.md` with a small table mapping
      rule fields to the phase that enforces them
- [ ] Write `docs/upgrades/m14-request-aware-rules.md` as a what's-new note with backward-compatibility guarantee,
      authoring surface tour, enforcement-phase map, and reload workflow
- [ ] Add `docs/policy/examples/request-rules.yaml` (methods + path prefix + query exact, minimum viable example)
- [ ] Add `docs/policy/examples/layered-merge.yaml` (two-layer additive + `merge_mode: replace`)
- [ ] Add troubleshooting entries: "policy rejected with schema error" and "request blocked unexpectedly"
- [ ] Extend `test_render_policy.py` with a baseline-IR snapshot test covering every agent catalog entry
- [ ] Scaffold `images/proxy/tests/integration/` with a pytest fixture that spawns `mitmdump -s enforcer.py` and
      yields a proxy URL + stdout capture handle
- [ ] Add integration scenarios: CONNECT allow, CONNECT block, method restriction, path prefix, query exact, SIGHUP
      reload swap, SIGHUP rejection with last-known-good
- [ ] Wire the integration suite into `.github/workflows/proxy-tests.yml`
- [ ] Add commented rich-rule example to `internal/embeddata/templates/user.policy.yaml`
- [ ] Run `go test ./...` and the full proxy test suite (unit + integration); confirm green

### Open Questions

1. **Do we invest in a mitmdump-subprocess integration harness, or defer integration coverage to a later milestone?**
   Draft default: build it now. The milestone risk note explicitly says "use a smaller set of proxy integration
   tests for wiring," and shipping m14 without any end-to-end proof the hooks fire as expected makes later
   milestones harder to trust. Cost is ~1 fixture + 7 focused tests. If the subprocess pattern proves flaky we can
   fall back to Docker-based integration in CI only.

2. **Is a dedicated `docs/upgrades/m14-...md` file warranted, or should the schema doc carry the feature-tour
   content inline?** Draft default: separate file, because the m8 guide set a precedent and users looking for
   "upgrade to m14" will grep `docs/upgrades/`. But we should be explicit that it's a what's-new note, not a
   migration, to avoid implying breakage.

3. **Should the template scaffolds (`user.policy.yaml`) ship a commented rich example, or stay minimal?** Draft
   default: a *commented* example. Minimal scaffolds hide the new capability from anyone who doesn't read the docs
   first. A commented example is discoverable without affecting active policy.

4. **Baseline IR snapshot test — inline expected structure, or golden files?** Draft default: inline assertions.
   Golden files would drift silently; inline structures force a reviewer to eyeball any catalog change. Seven
   agents × baseline-only expansion is small enough that inline stays readable.

## Outcome

### Acceptance Verification

Pending execution.

### Learnings

Pending execution.

### Follow-up Items

Pending execution.
