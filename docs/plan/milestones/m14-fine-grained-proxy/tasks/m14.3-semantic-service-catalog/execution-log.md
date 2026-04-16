# Execution Log: m14.3 - Semantic Service Catalog

## 2026-04-16 15:12 UTC - Drafted the task plan and locked the intended boundary

Reviewed the `m14` milestone plan, project learnings, decision record `005`, the current `render-policy`
implementation, the `m14.2` matcher boundary, and the downstream `m15` GitHub wrapper goals. The main planning
conclusion is that `m14.3` should not push GitHub-specific behavior into the matcher. Service semantics belong at
render time and should compile into the same canonical host-record IR that authored `domains` already use.

**Issue:** The current inline `SERVICE_DOMAINS` map can only emit host-wide trust. That blocks repo-scoped GitHub
policy authoring and creates pressure to add service-specific request logic in the runtime.

**Decision:** Plan `m14.3` around a dedicated renderer-side service catalog boundary plus direct catalog tests, keeping
`policy_matcher.py` generic.

**Open Question:** Additive host-record merging does not automatically narrow an earlier broad service declaration. The
task must resolve whether richer service entries get explicit replacement semantics or whether scoped service entries are
documented as additive only.
