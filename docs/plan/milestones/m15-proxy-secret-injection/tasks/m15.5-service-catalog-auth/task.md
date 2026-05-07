# Task: m15.5 - Service Catalog Auth

## Summary

Extend the service catalog boundary with auth-aware expansion, starting with GitHub `access` and `auth.secret`
shorthand for repo-scoped Git smart HTTP.

## Scope

- Keep auth semantics in the catalog and rendered rule metadata, not in the matcher or enforcer
- Add `access: read | readwrite` as the preferred GitHub repo-scoped capability field
- Keep `readonly` as deprecated compatibility input for unauthenticated GitHub repo-scoped entries
- Reject entries that specify both `access` and `readonly`
- Require explicit `access` when `auth` is present, and reject `auth` with deprecated `readonly`
- Expand GitHub `auth.secret` into rule-scoped `Authorization` injection using Basic auth with username
  `x-access-token`
- Preserve a catalog extension point for service-owned compatibility hints, but do not materialize agent-visible shim
  config in this task
- Exclude non-GitHub services, client compatibility shims, GitHub REST wrapper behavior, and user-facing docs

## Acceptance Criteria

- [ ] Catalog and renderer tests cover `access: read`, `access: readwrite`, deprecated `readonly`, mixed-field rejection,
      and auth-without-access rejection
- [ ] Authenticated GitHub `git` service entries render the same rule-scoped transform shape as explicit `domains`
      entries
- [ ] Existing unauthenticated `readonly` policies remain valid
- [ ] Catalog tests prove the emitted auth metadata is canonical and does not require GitHub-specific matcher behavior

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

- `images/proxy/service_catalog.py` - add GitHub `access` and `auth.secret` normalization, compatibility handling for
  `readonly`, and auth-aware Git smart-HTTP rule expansion
- `images/proxy/policy_injection.py` - reuse existing secret ID and transform normalization; adjust only if catalog
  construction needs a small shared helper
- `images/proxy/tests/test_service_catalog.py` - catalog unit coverage for access normalization, readonly compatibility,
  auth validation, and emitted Git rule transforms
- `images/proxy/tests/test_render_policy.py` - renderer coverage proving service-auth shorthand survives layered
  rendering, merge/dedupe, and outputs the same rule-scoped transform shape as explicit domain transforms

### Approach

Keep the implementation on the service-catalog side. `render-policy` should continue to ask
`service_catalog.expand_service_entry()` for canonical host-record fragments, then apply the existing merge and owner
tracking pipeline. Avoid adding GitHub branches to `render-policy`, `policy_matcher.py`, or `enforcer.py`.

Add a GitHub-only `access` field with values `read` and `readwrite`. For GitHub entries without auth, preserve existing
`readonly` input by normalizing `readonly: true` to `access: read` and `readonly: false` or omitted `readonly` to
`access: readwrite`. Reject `access` and `readonly` together so new policies have one capability spelling. For
non-GitHub services, keep the current `readonly` behavior and do not introduce `access`.

Add a narrow GitHub `auth` mapping with `secret` as the only supported field in this task. Validate the secret ID through
`policy_injection.normalize_secret_id()`. When `auth` is present:

- require `access` to be set explicitly
- reject `readonly`
- require repo-scoped `repos` / `surfaces`
- require the `git` surface to be present
- attach auth transforms only to `github.com` Git smart-HTTP rules, not to `api.github.com` API rules

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

Update GitHub expansion so `access: read` emits only upload-pack Git rules and read-only API methods when the API surface
is requested. `access: readwrite` should keep the existing write-capable behavior: unrestricted API methods and both
upload-pack and receive-pack Git rule pairs. Auth does not change the allowed URL set; it only attaches transform
metadata to the Git rules already selected by `access`.

Tests should first pin existing `readonly` behavior, then add the new spelling and auth cases. Include negative tests
for unsupported `auth` keys, invalid secret IDs, `auth` without `access`, `auth` with `readonly`, `auth` without `git`
surface, and mixed `access` / `readonly`. Renderer tests should prove layered service merge behavior still strips only
service-owned contributions and does not broaden transforms onto unrelated same-host domain rules.

### Implementation Steps

- [ ] Add GitHub `access` constants and normalization helpers
- [ ] Preserve existing unauthenticated `readonly` behavior by normalizing it to the new internal access model
- [ ] Reject `access` and `readonly` when both are present on a GitHub service entry
- [ ] Add GitHub `auth.secret` normalization and secret ID validation through `policy_injection.py`
- [ ] Reject `auth` without explicit `access`, with deprecated `readonly`, without repo-scoped surfaces, or without the
      `git` surface
- [ ] Add a catalog helper that builds canonical Basic `Authorization` transform metadata for GitHub token auth
- [ ] Attach the transform only to Git smart-HTTP rules emitted for authenticated GitHub service entries
- [ ] Keep API-surface rules unauthenticated and exclude GitHub REST wrapper behavior
- [ ] Add catalog tests for `access: read`, `access: readwrite`, existing `readonly`, validation failures, and canonical
      auth metadata
- [ ] Add renderer tests for authenticated GitHub shorthand, explicit-domain transform equivalence, and merge/dedupe
      behavior with unrelated same-host rules
- [ ] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [ ] Run `go test ./...` as a repo-wide sanity check

### Open Questions

- Should `auth` be allowed on a GitHub entry that includes both `api` and `git` surfaces? Planned default: allow it, but
  attach transforms only to `git` rules and cover that behavior in tests.
- Should `access` be accepted on non-repo-scoped GitHub baseline entries? Planned default: keep `access` focused on
  repo-scoped entries; preserve `readonly` for existing baseline catch-all compatibility unless implementation reveals a
  simpler non-breaking normalization path.
- Should authenticated rules use `on_existing_header: fail` or `replace` by default? Planned default: `fail` for direct
  Git smart-HTTP injection. `replace` is reserved for `m15.6` compatibility shims that intentionally send fake headers.

## Outcome

### Acceptance Verification

Pending implementation.

### Learnings

Pending implementation.

### Follow-up Items

Pending implementation.
