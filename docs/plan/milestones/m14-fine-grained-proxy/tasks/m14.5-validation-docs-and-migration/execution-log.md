# Execution Log: m14.5 - Validation, Docs, And Migration

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
