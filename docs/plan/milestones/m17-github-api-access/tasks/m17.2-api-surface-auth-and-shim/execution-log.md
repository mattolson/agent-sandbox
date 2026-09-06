# Execution Log: m17.2 - api surface auth and shim

## 2026-09-06 - Review fix: credential-carrying rules are https-only

**Issue:** Review found that api rules with `auth` inherited both `http` and `https`, so a client requesting
`http://api.github.com/repos/...` would have the real bearer token injected and forwarded in plaintext. The git
surface had the same defect since m15.
**Solution:** Fixed the class, not the instance. The catalog's `_apply_rule_transform` now drops `http` from any rule
it attaches a transform to, and the renderer's `apply_rule_transform` does the same for authored `domains`
transforms, failing rendering when a rule permitted only `http`. Unauthenticated rules keep both schemes.

**Issue:** The integration harness's fake upstream is plaintext, so every injection test would stop matching.
**Solution:** `remap_rendered_host` re-admits `http` on the rules of a host it remaps to the fake upstream, with a
docstring calling it a test-only downgrade. The enforcement test that builds rendered dicts directly was unaffected.

**Learning:** A security property that holds "because every rule happens to be https" is not a property. Attach the
invariant to the thing it protects: the transform, not the rule author.

## 2026-09-06 - Env shim kind landed with integration coverage

Added `kind: env` to `credential_shim.py`, wired the api surface to emit a `GH_TOKEN` hint and flip to
`on_existing_header: replace`, and pre-created the `env` fragment directory in both Dockerfiles.

**Decision:** The hint schema is kinded rather than growing a superset of keys. Common keys are `service`, `surface`,
`kind`, `host`, `secrets`; git-askpass adds `username` and `fake_password`; env adds `env_var` and `fake_value`.
Payload version stays 1 because existing payloads remain valid.

**Decision:** Env exports live in their own fragment (`env/exports.zsh`) sourced from `init.zsh`, mirroring
`git-askpass/env.zsh`, rather than one combined file. Each kind can be cleared independently.

**Learning:** The integration harness remaps a rendered host to the fake upstream. Parameterizing the host let the
api test reuse the same harness by mapping `api.github.com`, and the allowlist negatives ride along for free.

## 2026-09-06 - Bearer auth on the api surface

Replaced the `allow_auth` boolean with a `surface` parameter and two per-surface tables. `api.auth.secret` now
renders a bearer transform with `on_existing_header: fail`.

**Decision:** `auth` is optional on api at both access levels, unlike git readwrite which requires it. Git push
without auth cannot work; an api client can carry its own token. Documented as discouraged.

**Decision:** `client_shim` on api fails until the env kind exists, with a message naming the surface, so the
intermediate commit is honest about what it supports.

## 2026-09-06 - Readwrite allowlist

Replaced the method-less catch-all for `readwrite` with the enumerated write rules from decision 008.

**Issue:** Four existing tests asserted the old catch-all shape while testing something else (ordering, dedupe,
additivity).
**Solution:** Switched them to `read`, and added one dedicated test that pins the allowlist and asserts PUT and
DELETE never appear.
