# Execution Log: m15.6 - Credential Compatibility Shim

## 2026-05-10 01:56 UTC - Moved default secret source into resolver

Removed `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox` from the managed base compose template and scaffold repair
logic. `SecretResolver.from_env()` now defaults to `file:/run/secrets/agentbox` when the env var is unset or blank,
while still honoring `AGENTBOX_SECRET_SOURCE` as an explicit backend override.

**Decision:** Keep stable image-owned runtime defaults in proxy code instead of repeating them in generated compose.
The compose layer still owns the proxy-only secret mount; the resolver owns the default source scheme and path.

## 2026-05-10 01:53 UTC - Removed managed init-path env from compose

Removed `AGENTBOX_CREDENTIAL_SHIM_INIT_PATH` from the managed base compose template and scaffold repair logic. The
proxy entrypoint and agent shell initialization now rely on their built-in default path,
`/run/agentbox/credential-shims/init.zsh`, while still honoring `AGENTBOX_CREDENTIAL_SHIM_INIT_PATH` as a user override
when explicitly supplied through compose overrides.

## 2026-05-10 01:48 UTC - Pluralized runtime path and renamed volume

Renamed the shared Docker volume from `agentbox-credential-shim` to `proxy-credential-shims` and the mounted runtime
directory from `/run/agentbox/credential-shim` to `/run/agentbox/credential-shims`.

**Decision:** Use a plural runtime directory because it is a collection root for multiple credential shim fragments,
even though the current implementation only writes `git-askpass/env.zsh`.

## 2026-05-10 01:24 UTC - Split credential shim init and git askpass fragment

Updated the runtime path contract so new shells source the aggregate
`/run/agentbox/credential-shims/init.zsh`. The first concrete implementation now writes Git askpass exports to
`/run/agentbox/credential-shims/git-askpass/env.zsh`, and the aggregate init script sources that file only when a Git
askpass hint is active.

**Decision:** Use `init.zsh` as the stable entrypoint and per-shim subdirectories for implementation fragments. This
keeps the shell contract stable if later credential shims need their own env files or helper setup.

## 2026-05-10 01:10 UTC - Renamed rendered concept to credential shim

Renamed the renderer-owned concept from client shim to credential shim while preserving the authored
`git.auth.client_shim.kind` opt-in. The rendered policy key is now top-level `credential_shim`, the helper module is
`credential_shim.py`, and the runtime surface uses `/run/agentbox/credential-shims/init.zsh` in the
`proxy-credential-shims` named volume.

**Decision:** Keep `git.auth.client_shim` as the policy opt-in key. Under `git.auth`, the credential context is already
clear, and keeping the key stable avoids a noisy policy spelling change.

## 2026-05-10 00:56 UTC - Implemented credential shim

Implemented explicit `git.auth.client_shim.kind: git-askpass` support for GitHub Git auth. Shimmed rules now use
`on_existing_header: replace`, direct GitHub Git auth keeps `on_existing_header: fail`, and the renderer emits
service-owned top-level `credential_shim` metadata only for explicit opt-ins.

Added renderer-owned shell-fragment output under `/run/agentbox/credential-shims/`, refreshed by proxy startup and
successful policy reloads. The fragment only contains fake Git askpass values and logical secret IDs remain in rendered
metadata; resolved secret values stay proxy-only.

Added the fake askpass helper to the base image, source support in shell initialization, and the
`proxy-credential-shims` named volume shared read/write by `proxy` and read-only by `agent`. Scaffold sync now repairs
older managed base compose layers with the compatibility volume.

**Decision:** Write a no-op shell fragment when no shim is active. That clears stale fake setup without requiring the
agent container to infer policy state.

**Decision:** Pre-create the shared volume mount target with compatible ownership in both base and proxy images. Proxy
usually starts first, but the image should remain robust if a standalone agent run initializes the named volume.

**Verification:** `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` passed.

**Verification:** `go test ./...` passed.

## 2026-05-10 00:44 UTC - Renamed shim policy fields

Updated the task plan to use `git.auth.client_shim.kind: git-askpass` instead of
`git.auth.compatibility.mode: git-askpass`.

**Decision:** Prefer `client_shim` over `compatibility` because it names the mechanism more concretely and makes it
clear this is an explicit auth-adjacent shim, not a broad compatibility behavior. Prefer `kind` over `mode` because
the value selects a catalog-owned shim type rather than a runtime mode switch.

## 2026-05-09 18:15 UTC - Initial task plan

Created the M15.6 task plan after reviewing the M15 milestone, accumulated learnings, M15.1 through M15.5 task plans,
and the current proxy renderer, service catalog, injection, scaffold, and base image surfaces.

**Decision:** Keep the first compatibility shim GitHub Git-specific with an explicit `git.auth.client_shim.kind:
git-askpass` opt-in. A generic arbitrary env-var surface would be broader than the milestone needs and would weaken the
tie between service-owned auth semantics and proxy replacement rules.

**Decision:** Direct GitHub smart-HTTP injection remains the default and keeps `on_existing_header: fail`. Shimmed GitHub
Git auth uses `replace` only because the fake setup may intentionally send an existing `Authorization` header.

**Decision:** Treat rendered credential-shim metadata as service-catalog-owned output, not an author-facing top-level
policy field. User-authored top-level shim metadata should be rejected so this channel cannot become a second
compose-style environment override path.

**Observation:** The current runtime has no generic hot-update mechanism for agent process environment. The plan uses
an agent-visible credential shim volume plus shell initialization for new zsh sessions and leaves broader process-level
environment semantics out of scope.
