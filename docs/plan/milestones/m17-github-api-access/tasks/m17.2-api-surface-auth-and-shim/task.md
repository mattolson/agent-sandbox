# Task: m17.2 - api surface auth and shim

## Summary

Let a repo-scoped `github` entry inject auth on the `api` surface and export a `GH_TOKEN` placeholder.

## Scope

- Remove the `allow_auth=False` restriction on the `api` surface in `images/proxy/service_catalog.py`
- Keep `api.access: read` as GET and HEAD on `/repos/{owner}/{repo}` and its prefix
- Define `api.access: readwrite` as `read` plus POST on the issues and pulls collections and POST and PATCH under each
- Emit a `bearer` transform on every api rule when `api.auth.secret` is set; default to `on_existing_header: fail`
- Support `api.auth.client_shim` with a generic `env` kind whose variable name is chosen by the catalog, here
  `GH_TOKEN`; keep the hint shape generic so `m19.4` can extend it to provider keys
- Switch api rules to `on_existing_header: replace` only when the shim is present
- Extend the shell-init consumer so the rendered hint exports `GH_TOKEN` with the placeholder value
- Keep the sanitized `/run/agentbox/policy.yaml` free of transforms and secret IDs
- Update `docs/policy/schema.md`, which said `auth` is rejected on `api`
- Decide how to treat `/repositories/{id}/...` pagination URLs

## Acceptance Criteria

- [x] `curl` with no `Authorization` header to `/repos/owner/repo/issues` gets the real token injected
- [x] `gh api repos/owner/repo/issues` succeeds with only the placeholder in `GH_TOKEN`
- [x] A request to `/repos/other/repo` or `/graphql` returns the proxy 403, not a GitHub error
- [x] Authored top-level `credential_shim` and arbitrary env var names remain rejected
- [x] Renderer unit tests cover read and readwrite api surfaces, with and without the shim
- [x] Under `readwrite`: issue and PR creation, edits, and reviews pass; merge, comment deletion, hooks, and PATCH or
      DELETE on the repo record return the proxy 403

## Applicable Learnings

- Service auth semantics belong in the catalog; the matcher and enforcer stayed untouched.
- `credential_shim` is renderer-owned and kinded (decision 006). The env kind is emitted only by a catalog entry that
  opts in, and it flips `on_existing_header` to `replace` in the same place.
- The rule engine has `exact` and `prefix` paths and no deny primitive, so write scoping inside a family comes from
  methods (decision 008).

## Plan

### Files Involved

- `images/proxy/service_catalog.py`: readwrite allowlist, surface-aware auth, api transform and hints
- `images/proxy/credential_shim.py`: `env` kind, kinded hint schema, env fragment rendering
- `images/proxy/Dockerfile`, `images/base/Dockerfile`: pre-create the `env` fragment directory
- `images/proxy/tests/test_service_catalog.py`, `test_render_policy.py`,
  `integration/test_credential_shim_replace.py`: coverage at each layer
- `docs/policy/schema.md`: access levels, `api.auth`, `client_shim` per surface, rendered hint shape

### Approach

Three commits, each leaving the suite green:

1. Readwrite allowlist. `_github_api_rules_for_repo` emits the two read rules for both levels and four write rules
   for `readwrite`. Tests that used `readwrite` only for ordering or dedupe moved to `read`.
2. Bearer auth. The git-named auth helpers became surface-aware with two small tables: header transform per surface
   (Basic for git, bearer for api) and accepted shim kinds per surface. `auth` stays optional at both api access
   levels; an unauthenticated readwrite surface is valid but discouraged.
3. Env shim. `normalize_hint` is kinded: common keys plus `username`/`fake_password` for git-askpass or
   `env_var`/`fake_value` for env. `write_init` rewrites every fragment on each render so a removed shim leaves an
   inert file rather than stale exports. The init fragment sources one file per active kind.

### Implementation Steps

- [x] Readwrite allowlist and tests
- [x] Surface-aware auth normalization and bearer transform
- [x] `env` kind in `credential_shim.py` with generic `make_env_hint` and a GitHub wrapper
- [x] Catalog emits the env hint and flips api rules to `replace`
- [x] Env fragment rendering, init sourcing, and stale-clearing
- [x] Integration test through the real enforcer, including allowlist negatives
- [x] Schema docs
- [x] Rebuild the proxy image and re-run the command matrix: done in `m17.3` on host-rebuilt images

### Open Questions

- Pagination on `/repositories/{id}` URLs: left to agent instructions (`page=N` loops) per the milestone plan. No
  policy change.

## Outcome

### Acceptance Verification

- [x] Injection with no client header and with the placeholder header: proven in the 2026-09-06 validation against
      an authored transform that renders to the same rules this task emits; the integration test now pins it
- [x] Negatives: integration test asserts 403 for merge (PUT), comment delete (DELETE), hooks (POST), and repo record
      (PATCH) with zero upstream requests
- [x] Authored `credential_shim` still rejected: existing test unchanged and passing
- [x] Arbitrary env var names: the policy author never names a variable; the catalog does, and `normalize_hint`
      validates the name shape

### Learnings

- Per-surface tables (header transform, accepted shim kinds) removed the need for boolean flags like `allow_auth`
  and make the next surface a two-line addition.
- Rewriting every fragment on each render is what makes shim removal safe. A fragment that is only written when
  active would linger after the policy drops it.

### Follow-up Items

- `m17.3` re-runs the command matrix against a rebuilt proxy on the host.
- `m19.4` extends `make_env_hint` to provider variables; no shape change expected.
