# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent Sandbox creates locked-down local sandboxes for running AI coding agents (Claude Code, Codex, etc.) with minimal filesystem access and restricted outbound network. Enforcement uses two layers: an mitmproxy sidecar that enforces a domain allowlist at the HTTP/HTTPS level, and iptables rules that block all direct outbound to prevent bypassing the proxy.

**Note**: During development of this project, Claude Code operates inside a locked-down container using the docker compose method. This means git push/pull and other network operations outside the allowlist will fail from within the container. Handle git operations from the host.

## Development Environment

This project uses Docker Compose with a proxy sidecar. Two modes are available:

- **Devcontainer mode** (`.devcontainer/docker-compose.yml`) - For VS Code users, uses published images from ghcr.io
- **CLI mode** (`docker-compose.yml`) - For terminal usage, uses locally-built `:local` images

Both use separate compose files to allow running simultaneously without conflicts.

The container runs Debian bookworm with:
- Non-root `dev` user (uid/gid 500)
- Zsh with minimal prompt
- Network lockdown via `init-firewall.sh` at container start
- SSH disabled (git must use HTTPS, URLs are auto-rewritten)

### Setup (one-time)

Copy the policy files to your host:
```bash
mkdir -p ~/.config/agent-sandbox/policies
cp docs/policy/examples/claude.yaml ~/.config/agent-sandbox/policies/claude.yaml
cp docs/policy/examples/claude-devcontainer.yaml ~/.config/agent-sandbox/policies/claude-devcontainer.yaml
```

Build local images:
```bash
./images/build.sh
```

### Key Paths Inside Container
- `/workspace` - Your repo (bind mount)
- `/home/dev/.claude` - Claude Code state (named volume, persists per-project)
- `/commandhistory` - Bash/zsh history (named volume)

### Useful Aliases
- `yolo-claude` (or `yc`) - Runs `claude --dangerously-skip-permissions` from /workspace

## Network Policy

Two layers of enforcement:

1. **Proxy** (mitmproxy sidecar) - Enforces a domain allowlist at the HTTP/HTTPS level. Blocks non-allowed domains with 403.
2. **Firewall** (iptables) - Blocks all direct outbound. Only the Docker host network (where the proxy lives) is reachable.

### Policy Format

The proxy reads policy from `/etc/mitmproxy/policy.yaml`:

```yaml
services:
  - github  # Expands to github.com, *.github.com, *.githubusercontent.com

domains:
  - api.anthropic.com
  - sentry.io
```

Available services are hardcoded in `images/proxy/addons/enforcer.py`:
- `github`: github.com, *.github.com, *.githubusercontent.com
- `claude`: *.anthropic.com, *.claude.ai, *.sentry.io, *.datadoghq.com
- `vscode`: VS Code marketplace and update infrastructure

Adding a new service requires modifying `enforcer.py`. For one-off domains, use the `domains:` list instead.

### Customizing the Policy

Policy files live on the host at `~/.config/agent-sandbox/policies/`. The compose files mount the appropriate policy:

- CLI mode: `claude.yaml`
- Devcontainer mode: `claude-devcontainer.yaml`

Policy must come from outside the workspace for security (prevents agent from modifying its own allowlist).

## Architecture

Four components:

1. **Images** (`images/`) - Base image, agent-specific images, and proxy image
2. **Templates** (`templates/`) - Ready-to-copy templates for each supported agent
3. **Runtime** (`docker-compose.yml`) - Docker Compose stack for developing this project
4. **Devcontainer** (`.devcontainer/`) - VS Code devcontainer for developing this project

The base image contains the firewall script and common tools. Agent images extend it with agent-specific software. The proxy image runs mitmproxy with the policy enforcement addon.

## Key Principles

- **Security-first**: Changes must maintain or improve security posture. Never bypass firewall restrictions without explicit user request.
- **Reproducibility**: Pin images by digest, not tag. Prefer explicit configs over defaults.
- **Agent-agnostic**: Core changes should support multiple agents. Agent-specific logic belongs in agent-specific images.
- **Policy-as-code**: Network policies should be reviewed like source code.

## Testing Changes

The firewall (`init-firewall.sh`) runs two verification tests on startup:
1. Waits up to 30s for proxy to become reachable on port 8080
2. Verifies direct outbound is blocked (curl to example.com fails)

To test proxy enforcement:
```bash
# Should return 403 (blocked)
curl -x http://proxy:8080 https://example.com

# Should succeed (allowed by policy)
curl -x http://proxy:8080 https://github.com
```

After modifying a policy file or proxy addon:
1. Rebuild the proxy image (`./images/build.sh proxy`)
2. Restart: `docker compose up -d proxy`
3. Check proxy logs: `docker compose logs proxy`

## Image Versioning

GitHub Actions builds images on:
- Push to main (when `images/**` changes)
- Daily cron that checks for new Claude Code releases on npm
- Manual workflow dispatch

Tags applied to `agent-sandbox-claude`:
- `latest`: Most recent build from main
- `sha-<commit>`: Git commit that triggered the build
- `claude-X.Y.Z`: Claude Code version installed in the image

The daily `check-claude-version.yml` workflow queries npm for the latest Claude Code version and triggers a rebuild if no image exists with that version tag.

## Known Workarounds

**HTTP/2 disabled for Go programs**: The compose files set `GODEBUG=http2client=0` to disable HTTP/2 in the gh CLI. This avoids header validation errors when requests pass through mitmproxy.

## Shell Customization

Drop scripts in `~/.config/agent-sandbox/shell.d/*.sh` on the host. They're sourced at shell startup (read-only mount). The shell-init chain is root-owned to prevent the agent from injecting commands.

## Target Platform

Primary: Colima on Apple Silicon (macOS). Should work on any Docker-compatible runtime.
