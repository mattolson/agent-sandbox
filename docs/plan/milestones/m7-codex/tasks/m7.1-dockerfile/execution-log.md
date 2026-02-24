# Execution Log: m7.1 - Codex Agent Dockerfile

## 2026-02-23 - Implementation complete

Created both files:
- `images/agents/codex/config.toml` - minimal config with `sandbox_mode = "danger-full-access"`
- `images/agents/codex/Dockerfile` - follows Claude agent pattern

**Issue:** Base image doesn't include `~/.local/bin` in PATH or create the directory.
**Solution:** Added `mkdir -p /home/dev/.local/bin` in the root section and `ENV PATH="/home/dev/.local/bin:$PATH"` after switching to dev user. Same pattern as Claude Dockerfile.

**Decision:** Install binary to `~/.local/bin` rather than `/usr/local/bin`. This keeps the install as the dev user (matching Claude pattern) and avoids needing to switch back to root for the install step.

**Decision:** Use musl variant over gnu variant for the binary. Musl is statically linked with no external dependencies, while gnu requires matching glibc and libssl versions. Better for container portability.

## 2026-02-23 - Asset naming verified

Researched GitHub releases to confirm asset naming convention:
- Tarballs: `codex-{triple}.tar.gz` (e.g., `codex-x86_64-unknown-linux-musl.tar.gz`)
- Binary inside tarball: `codex-{triple}` (single file, no directory structure)
- Tags: `rust-v{version}` (e.g., `rust-v0.104.0`)
- Latest stable: 0.104.0
- Both musl and gnu variants available; musl is the right choice for containers

## 2026-02-23 - Planning started

Reviewed existing agent Dockerfiles (Claude, Copilot) and build.sh to understand patterns. Claude is the closest analog since it's simpler (no Node.js). Key patterns to follow:
- ARG BASE_IMAGE with default
- EXTRA_PACKAGES validation block
- Config directory creation as root
- Switch to dev user before agent install
- OCI labels at the end
