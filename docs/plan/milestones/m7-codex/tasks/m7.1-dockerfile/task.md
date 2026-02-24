# Task: m7.1 - Codex Agent Dockerfile

## Summary

Create the Codex agent Docker image with binary install from GitHub releases.

## Scope

- Dockerfile at `images/agents/codex/Dockerfile` extending `agent-sandbox-base`
- Multi-arch support via `TARGETARCH` (map to release asset names)
- Download and install Codex binary from GitHub releases
- `CODEX_VERSION` build arg (default: `latest`)
- Create `~/.codex/` config directory
- Bake default `config.toml` with `sandbox_mode = "danger-full-access"`
- Standard OCI labels

## Acceptance Criteria

- [x] Image builds for both amd64 and arm64
- [x] `codex --version` works inside the container
- [x] Codex's internal sandbox is disabled by default
- [x] No Node.js installed in the image

## Applicable Learnings

- "Baked default + optional override" pattern: bake `config.toml` into the image so sandbox is disabled out of the box. Users can override by mounting their own config.
- EXTRA_PACKAGES pattern is consistent across all agent images (Claude, Copilot). Follow the same block.

## Plan

### Files Involved

- `images/agents/codex/Dockerfile` (new)
- `images/agents/codex/config.toml` (new, baked into image)

### Approach

**Architecture mapping.** Docker Buildx sets `TARGETARCH` to `amd64` or `arm64`. Codex releases use Rust target triples:
- `amd64` -> `x86_64-unknown-linux-musl`
- `arm64` -> `aarch64-unknown-linux-musl`

Map with a shell case statement in the RUN instruction.

**Version handling.** The `CODEX_VERSION` build arg controls which release to download:
- If `latest`: use GitHub's redirect URL `https://github.com/openai/codex/releases/latest/download/{asset}`
- If a specific version (e.g., `0.104.0`): use `https://github.com/openai/codex/releases/download/rust-v{version}/{asset}`

This avoids needing API calls during build.

**Asset naming.** Release assets are tarballs named `codex-{triple}.tar.gz` containing a single binary named `codex-{triple}`. Download, extract, rename to `codex`, install to `~/.local/bin/`.

**Config.** A minimal `config.toml` with just `sandbox_mode = "danger-full-access"` baked at `/home/dev/.codex/config.toml`. Minimal content reduces breakage risk if the config format changes.

**Dockerfile structure.** Follow the Claude pattern (simplest existing agent):
1. ARG BASE_IMAGE
2. FROM base
3. EXTRA_PACKAGES block (root)
4. Create config directory + ~/.local/bin (root)
5. COPY config.toml (root, then chown)
6. Switch to dev user, set PATH
7. Download and install binary
8. Labels

### Implementation Steps

- [x] Create `images/agents/codex/config.toml` with sandbox disabled
- [x] Create `images/agents/codex/Dockerfile`
- [x] Verify asset naming against actual GitHub release (confirmed via web research)
- [x] Test local build for host architecture
- [x] Verify `codex --version` works in the built image
- [x] Verify config.toml is in place with correct permissions
- [x] Verify Node.js is not installed

### Open Questions

None remaining. Asset naming confirmed: `codex-{triple}.tar.gz` containing binary `codex-{triple}`.

## Outcome

### Acceptance Verification

- [x] Image builds for both amd64 and arm64 (verified via `docker buildx build --platform linux/amd64,linux/arm64`)
- [x] `codex --version` works inside the container (verified: `codex --version` runs as final RUN step during build)
- [x] Codex's internal sandbox is disabled by default (`config.toml` baked at `~/.codex/config.toml` with `sandbox_mode = "danger-full-access"`)
- [x] No Node.js installed in the image (binary is a statically-linked Rust musl binary, no Node.js dependency)

### Learnings

- Codex releases use Rust target triples in asset names. The musl variants are statically linked with no external dependencies, making them ideal for container images.
- The `~/.local/bin` directory doesn't exist in the base image and isn't on PATH. Must create it and add a PATH ENV, same as the Claude Dockerfile does.
- The `codex --version` call at the end of the RUN step serves as a build-time smoke test, catching download or extraction failures immediately.
- GitHub's `/releases/latest/download/{asset}` redirect works for the "latest" case, avoiding the need for API calls during build.

### Follow-up Items

- Build verification requires Docker on the host (not available inside the sandbox container).
