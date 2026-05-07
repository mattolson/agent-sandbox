# Execution Log: m15.5 - Service Catalog Auth

## 2026-05-07 04:00 UTC - Initial task plan

Created the m15.5 task plan from the milestone breakdown and reviewed the existing GitHub service catalog, render-policy
merge pipeline, explicit domain transform schema from m15.1, file resolver and runtime injection behavior from m15.2 and
m15.4, and the current catalog and renderer test coverage.

**Decision:** Keep m15.5 focused on catalog-auth authoring and rendered rule metadata. Secret resolution, request
mutation, runtime secret mounting, client compatibility shims, and user-facing docs are already owned by adjacent m15
tasks.

**Decision:** Treat `access` as the new internal capability model for GitHub repo-scoped entries while preserving
existing unauthenticated `readonly` behavior as compatibility input.

**Decision:** Default GitHub direct-injection shorthand to `on_existing_header: fail`. Header replacement should be
introduced only when a later compatibility shim deliberately causes the client to send fake auth material.

**Observation:** The existing catalog already owns GitHub Git read/write expansion. The main implementation risk is not
matching behavior; it is making sure auth transforms stay rule-scoped through service expansion, layered merge, and
dedupe.
