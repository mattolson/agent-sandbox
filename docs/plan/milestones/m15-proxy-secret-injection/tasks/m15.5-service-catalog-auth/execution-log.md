# Execution Log: m15.5 - Service Catalog Auth

## 2026-05-09 17:59 UTC - Implementation complete

Implemented surface-scoped GitHub service catalog auth. The catalog now accepts repo-scoped `git` and `api` mappings,
rejects the unshipped `surfaces` field, rejects repo-scoped `readonly`, top-level `access`, and top-level `auth`, and
requires at least one of `git` or `api` when `repos` is present. Broad `name: github` behavior without `repos` remains
unchanged.

Git rules now support `git.access: read` without auth for public clone/fetch and require `git.auth.secret` for
`git.access: readwrite`. Authenticated Git rules emit canonical rule-scoped Basic `Authorization` transform metadata
with username `x-access-token`; API rules remain unauthenticated and `api.auth` is rejected for later REST work.

Updated catalog, renderer, and matcher tests from the unshipped `surfaces` shape to the `git` / `api` mapping model.
Added coverage for rejected fields, missing surface defaults, unauthenticated read, unauthenticated readwrite rejection,
auth transform metadata, merge behavior, and generic matcher enforcement.

Verified with:

- `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- `go test ./...`

**Decision:** Keep direct Git auth `on_existing_header: fail`. Replacement remains a compatibility-shim concern for
`m15.6`.

**Learning:** When a renderer helper gains a new shared-module dependency, import-path tests must copy and isolate that
dependency too. Otherwise the test can accidentally pass by reusing a module already loaded from the repo path.

**Learning:** Keep internal names distinct from rejected author-facing fields. The catalog now uses `surface_configs`
internally so `surfaces` remains clearly an unsupported policy field.

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

**Decision:** `api.auth` is reserved and rejected in m15.5. Provider API-key behavior belongs to `m16`, and GitHub REST
wrapper behavior belongs to `m17`.

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
