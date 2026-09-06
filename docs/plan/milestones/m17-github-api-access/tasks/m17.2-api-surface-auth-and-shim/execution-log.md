# Execution Log: m17.2 - api surface auth and shim

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
