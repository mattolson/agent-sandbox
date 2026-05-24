# Task: m15.5 - Service Catalog Auth

## Summary

Extend the service catalog boundary with surface-scoped auth-aware expansion, starting with GitHub `git.access` and
`git.auth.secret` shorthand for repo-scoped Git smart HTTP.

## Scope

- Keep auth semantics in the catalog and rendered rule metadata, not in the matcher or enforcer
- Add surface-scoped `git.access: read | readwrite` as the preferred GitHub Git capability field
- Add `git.auth.secret` as the GitHub Git token shorthand; do not support top-level `auth`
- Allow an optional `api.access` surface shape for repo-scoped API rules, but keep API auth out of scope for this task
- Require at least one of `git` or `api` when `repos` is present; do not infer a default repo-scoped surface
- Preserve existing broad `name: github` behavior when `repos` is absent
- Remove the unshipped repo-scoped `surfaces` field from the planned schema
- Reject `surfaces`, repo-scoped `readonly`, top-level `access`, and top-level `auth` on GitHub repo-scoped entries
- Allow `git.access: read` without `git.auth` for public clone/fetch
- Require `git.auth` when `git.access: readwrite`
- Require explicit `git.access` when `git.auth` is present
- Expand GitHub `git.auth.secret` into rule-scoped `Authorization` injection using Basic auth with username
  `x-access-token`
- Preserve a catalog extension point for service-owned compatibility hints, but do not materialize agent-visible shim
  config in this task
- Exclude non-GitHub services, client compatibility shims, GitHub REST wrapper behavior, and user-facing docs

## Acceptance Criteria

- [x] Catalog and renderer tests cover `git.access: read`, `git.access: readwrite`, optional `api.access`, rejected
      `surfaces`, rejected repo-scoped `readonly`, and auth-without-access rejection
- [x] `git.access: read` without `git.auth` remains valid and emits unauthenticated upload-pack rules
- [x] `git.access: readwrite` without `git.auth` is rejected
- [x] GitHub entries with `repos` but neither `git` nor `api` are rejected
- [x] GitHub entries without `repos` preserve the existing broad service expansion and do not infer repo-scoped behavior
- [x] Authenticated GitHub `git` service entries render the same rule-scoped transform shape as explicit `domains`
      entries
- [x] Repo-scoped GitHub entries select enabled behavior through `git` and `api` mappings only
- [x] Catalog tests prove the emitted auth metadata is canonical and does not require GitHub-specific matcher behavior

## Applicable Learnings

- The renderer-side service catalog should own service semantics and emit canonical host-record fragments. The matcher
  and enforcer should stay generic and consume rule-scoped transform metadata.
- Rule-scoped policy metadata should be attached before host-record merge and dedupe so the existing full-rule identity
  preserves credential scope without host-wide side effects.
- GitHub Git read/write semantics belong inside the catalog. Read access emits the upload-pack pair; readwrite adds the
  receive-pack pair.
- Canonical catalog output should not be re-normalized inside the renderer. Service auth should reuse the m15.1
  `policy_injection.py` helpers before fragments enter the render merge path.
- Transformed HTTPS rules force request inspection at CONNECT time in the matcher/enforcer path, so catalog-auth rules
  can rely on the m15.4 generic injection behavior once they render the canonical transform shape.
- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs.

## Plan

### Files Involved

- `images/proxy/service_catalog.py` - add GitHub `git.access`, `git.auth.secret`, and optional `api.access`
  normalization, remove the unshipped repo-scoped `surfaces` path, and add auth-aware Git smart-HTTP rule expansion
- `images/proxy/policy_injection.py` - reuse existing secret ID and transform normalization; adjust only if catalog
  construction needs a small shared helper
- `images/proxy/tests/test_service_catalog.py` - catalog unit coverage for surface-scoped access normalization,
  `surfaces` rejection, repo-scoped `readonly` rejection, auth validation, and emitted Git rule transforms
- `images/proxy/tests/test_render_policy.py` - renderer coverage proving service-auth shorthand survives layered
  rendering, merge/dedupe, and outputs the same rule-scoped transform shape as explicit domain transforms

### Approach

Keep the implementation on the service-catalog side. `render-policy` should continue to ask
`service_catalog.expand_service_entry()` for canonical host-record fragments, then apply the existing merge and owner
tracking pipeline. Avoid adding GitHub branches to `render-policy`, `policy_matcher.py`, or `enforcer.py`.

Add GitHub-only surface mappings for repo-scoped entries:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
```

Presence of `git` selects the Git smart-HTTP surface. Presence of `api` selects the GitHub REST API repo surface. Each
surface owns its access level, so an entry that needs both surfaces can express different capabilities without one
ambiguous top-level access field:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
    api:
      access: read
```

Do not support the earlier planned `surfaces` list. It has not shipped, and `git:` / `api:` are a cleaner selector:
presence of the surface mapping already says which behavior is enabled. Reject `surfaces` on GitHub repo-scoped entries
instead of carrying a deprecated input path. Also reject repo-scoped `readonly`; surface access should be spelled as
`git.access` or `api.access`. For non-GitHub services, keep the current `readonly` behavior and do not introduce
`access`.

There should be no default surface for repo-scoped GitHub entries. If `repos` is present, require at least one of `git`
or `api`; reject an entry that only names repositories. If `repos` is absent, preserve the existing broad `name: github`
service behavior and do not allow `git` / `api` mappings, because those mappings are meaningful only when tied to
specific repositories.

Add a narrow GitHub `git.auth` mapping with `secret` as the only supported field in this task. Validate the secret ID
through `policy_injection.normalize_secret_id()`. When `git.auth` is present:

- require `git.access` to be set explicitly
- reject top-level `auth`
- reject `surfaces`, top-level `access`, and repo-scoped `readonly`
- require repo-scoped `repos`
- attach auth transforms only to `github.com` Git smart-HTTP rules, not to `api.github.com` API rules

`git.auth` is optional for `git.access: read`. That keeps public repo clone/fetch policies simple:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: read
```

`git.auth` is required for `git.access: readwrite`. Emitting push-capable `git-receive-pack` paths without credentials
is not useful for GitHub and weakens the policy model by making write access look available when the proxy has no
credential path:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
```

Reject `api.auth` for now with a clear reserved/unsupported error. Provider API-key injection belongs to `m16`, GitHub
REST wrapper behavior belongs to `m17`, and M15.5 should not imply API credential injection.

For authenticated Git rules, emit the same canonical rule-scoped transform shape as explicit `domains[].transform`
authoring:

```yaml
transform:
  request:
    headers:
      Authorization:
        secret: github.agent-sandbox.push-token
        transform:
          type: basic
          username: x-access-token
    on_existing_header: fail
```

Use a small catalog helper to construct this transform and pass it through `policy_injection.normalize_rule_transform()`
before attaching it to rules. That keeps service-owned auth output canonical without making the renderer re-normalize
catalog fragments. Keep `on_existing_header: fail` as the default for direct Git smart-HTTP injection. Replacement for
fake agent-visible credentials belongs to `m15.6`.

Update GitHub expansion so `git.access: read` emits only upload-pack Git rules. `git.access: readwrite` should keep the
existing write-capable Git behavior by adding the receive-pack rule pair. For `api.access`, `read` emits read-only API
methods and `readwrite` preserves the existing unrestricted API method behavior. Auth does not change the allowed URL
set; it only attaches transform metadata to the Git rules already selected by `git.access`.

Tests should first pin unaffected simple-service `readonly` behavior, then add the new GitHub repo-scoped spelling and
auth cases. Include negative tests for unsupported `git.auth` keys, invalid secret IDs, top-level `auth`, top-level
`access`, `surfaces`, repo-scoped `readonly`, `git.auth` without `git.access`, `api.auth`, and invalid surface access
values. Include negative tests for `repos` without either `git` or `api`, and for `git` / `api` mappings without
`repos`. Include positive tests for unauthenticated `git.access: read`, authenticated `git.access: read`, authenticated
`git.access: readwrite`, and the existing broad `name: github` expansion without `repos`, plus a negative test for
unauthenticated `git.access: readwrite`. Renderer tests should prove layered service merge behavior still strips only
service-owned contributions and does not broaden transforms onto unrelated same-host domain rules.

### Implementation Steps

- [x] Add GitHub surface access constants and normalization helpers for `git.access` and `api.access`
- [x] Reject repo-scoped GitHub entries that set `repos` without at least one of `git` or `api`
- [x] Reject `git` / `api` mappings when `repos` is absent
- [x] Remove the unshipped repo-scoped `surfaces` normalization path
- [x] Reject `surfaces`, top-level `access`, and repo-scoped `readonly` on GitHub repo-scoped entries
- [x] Add GitHub `git.auth.secret` normalization and secret ID validation through `policy_injection.py`
- [x] Reject top-level `auth`, `api.auth`, `git.auth` without explicit `git.access`, and `git.auth` without repo-scoped
      `repos`
- [x] Allow unauthenticated `git.access: read` for public clone/fetch
- [x] Reject unauthenticated `git.access: readwrite`
- [x] Add a catalog helper that builds canonical Basic `Authorization` transform metadata for GitHub token auth
- [x] Attach the transform only to Git smart-HTTP rules emitted for authenticated GitHub service entries
- [x] Keep API-surface rules unauthenticated and exclude GitHub REST wrapper behavior
- [x] Add catalog tests for `git.access: read`, `git.access: readwrite`, `api.access`, `surfaces` rejection,
      repo-scoped `readonly` rejection, repos-without-surface rejection, surface-without-repos rejection,
      unauthenticated read, unauthenticated readwrite rejection, validation failures, and canonical auth metadata
- [x] Add renderer tests for authenticated GitHub shorthand, explicit-domain transform equivalence, and merge/dedupe
      behavior with unrelated same-host rules
- [x] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] Run `go test ./...` as a repo-wide sanity check

### Open Questions

- Resolved: `auth` and `access` should be surface-scoped. The preferred shape is `git.access` plus `git.auth`, not
  separate top-level fields.
- Resolved: the unshipped `surfaces` field should be removed instead of preserved as compatibility input. Repo-scoped
  GitHub entries use `git` and `api` mappings only.
- Resolved: `git.auth` is optional for `git.access: read` so public repositories can be cloned without a token, but
  required for `git.access: readwrite`.
- Resolved: repo-scoped GitHub entries have no default surface. `repos` requires at least one of `git` or `api`, while
  `name: github` without `repos` preserves existing broad service expansion.
- Resolved: `git` / `api` mappings are not accepted without `repos`; the new surface mappings are repo-scoped.
- Resolved: authenticated Git rules use `on_existing_header: fail`. `replace` is reserved for `m15.6` compatibility
  shims that intentionally send fake headers.

## Outcome

### Acceptance Verification

- [x] Catalog and renderer tests cover the surface-scoped GitHub schema, rejected unshipped fields, auth validation, and
      canonical rule-scoped transform metadata.
- [x] `git.access: read` without `git.auth` emits unauthenticated upload-pack rules.
- [x] `git.access: readwrite` without `git.auth` is rejected.
- [x] `repos` without `git` or `api` is rejected, while broad `name: github` without `repos` still emits the baseline
      GitHub hosts.
- [x] Authenticated GitHub Git service entries render Basic `Authorization` transforms only on Git smart-HTTP rules.
- [x] The generic matcher integration test enforces the rendered GitHub rules without GitHub-specific matcher behavior.
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] `go test ./...`

### Learnings

- When a renderer helper gains a new shared-module dependency, import-path tests must copy and isolate that dependency
  too. Otherwise the test can accidentally pass by reusing a module already loaded from the repo path.
- Keep internal names distinct from rejected author-facing fields. The catalog uses `surface_configs` internally so the
  rejected `surfaces` field stays clearly author-facing only.

### Follow-up Items

- `m15.8` should update `docs/policy/schema.md` and `docs/policy/examples/github-repos.yaml`; those docs still describe
  the pre-M15.5 `surfaces` / `readonly` shape.
