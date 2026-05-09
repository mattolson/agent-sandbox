# Execution Log: m15.5 - Service Catalog Auth

## 2026-05-09 05:22 UTC - Repo-scoped entries have no default surface

Updated the task plan and parent milestone entry to make repo-scoped GitHub surface selection explicit.

**Decision:** If `repos` is present, require at least one of `git` or `api`. Do not infer a default repo-scoped surface.

**Decision:** If `repos` is absent, preserve the existing broad `name: github` service expansion and reject `git` / `api`
mappings because the new surface mappings are repo-scoped.

## 2026-05-09 05:07 UTC - Read auth optional, write auth required

Updated the task plan and parent milestone entry to distinguish public read from write-capable Git access.

**Decision:** `git.access: read` can omit `git.auth` so public clone/fetch policies do not require a token.

**Decision:** `git.access: readwrite` requires `git.auth`. Emitting `git-receive-pack` rules without credentials is not
useful for GitHub and makes the policy's write claim ambiguous.

## 2026-05-09 04:39 UTC - Unshipped surfaces syntax removed

Updated the task plan and parent milestone entry to remove repo-scoped `surfaces` from M15.5 instead of preserving it as
deprecated compatibility input. The selected surface is now expressed only by the presence of `git` or `api` mappings.

**Decision:** Reject repo-scoped `surfaces` in M15.5 because it has not shipped and duplicates the new surface mapping
syntax.

**Decision:** Reject repo-scoped `readonly` as part of the same cleanup. Repo-scoped access should be explicit under
`git.access` or `api.access`.

## 2026-05-09 04:11 UTC - Surface-scoped auth shape adopted

Updated the task plan and parent milestone entry to replace the flat `surfaces` plus top-level `access` / `auth` model
with surface-scoped GitHub mappings. The preferred policy shape is now `git.access` plus `git.auth.secret`; optional
`api.access` can describe repo-scoped API rules without implying API auth.

**Decision:** Top-level `auth` is rejected. Secret-backed auth belongs under the surface that consumes it, starting with
`git.auth`.

**Decision:** Superseded by the 2026-05-09 04:39 UTC entry. At this point the plan still kept legacy `surfaces` /
`readonly` for unauthenticated GitHub repo-scoped policies, but that compatibility path was removed after confirming the
syntax had not shipped.

**Decision:** `api.auth` is reserved and rejected in m15.5. GitHub REST wrapper and API credential behavior belongs to
`m16`.

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
