# Execution Log: m15.6 - Client Compatibility Shim

## 2026-05-10 00:44 UTC - Renamed shim policy fields

Updated the task plan to use `git.auth.client_shim.kind: git-askpass` instead of
`git.auth.compatibility.mode: git-askpass`. The rendered sidecar IR and helper module now use `client_shim` naming too,
so the plan has one term for the agent-visible fake setup channel.

**Decision:** Prefer `client_shim` over `compatibility` because it names the mechanism more concretely and makes it
clear this is an explicit client-facing shim, not a broad compatibility behavior. Prefer `kind` over `mode` because the
value selects a catalog-owned shim type rather than a runtime mode switch.

## 2026-05-09 18:15 UTC - Initial task plan

Created the M15.6 task plan after reviewing the M15 milestone, accumulated learnings, M15.1 through M15.5 task plans,
and the current proxy renderer, service catalog, injection, scaffold, and base image surfaces.

**Decision:** Keep the first compatibility shim GitHub Git-specific with an explicit `git.auth.client_shim.kind:
git-askpass` opt-in. A generic arbitrary env-var surface would be broader than the milestone needs and would weaken the
tie between service-owned auth semantics and proxy replacement rules.

**Decision:** Direct GitHub smart-HTTP injection remains the default and keeps `on_existing_header: fail`. Shimmed GitHub
Git auth uses `replace` only because the fake setup may intentionally send an existing `Authorization` header.

**Decision:** Treat rendered `client_shim` as service-catalog-owned output, not an author-facing top-level policy
field. User-authored top-level `client_shim` should be rejected so this channel cannot become a second compose-style
environment override path.

**Observation:** The current runtime has no generic hot-update mechanism for agent process environment. The plan uses a
shared non-secret compatibility volume plus shell initialization for new zsh sessions and leaves broader process-level
environment semantics out of scope.
