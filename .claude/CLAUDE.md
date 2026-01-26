# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent Sandbox creates locked-down local sandboxes for running AI coding agents (Claude Code, Codex, etc.) with minimal filesystem access and restricted outbound network. Enforcement uses two layers: an mitmproxy sidecar that enforces a domain allowlist at the HTTP/HTTPS level, and iptables rules that block all direct outbound to prevent bypassing the proxy.

**Note**: During development of this project, Claude Code operates inside a locked-down container using the docker compose method. This means git push/pull and other network operations outside the allowlist will fail from within the container. Handle git operations from the host.

## Development Environment

This project uses Docker Compose with a proxy sidecar. Two modes are available:

- **Devcontainer mode** (`.devcontainer/docker-compose.yml`) - For VS Code users
- **CLI mode** (`docker-compose.yml`) - For terminal usage

Both use separate compose files to allow running simultaneously without conflicts.

The container runs Debian bookworm with:
- Non-root `dev` user (uid/gid 500)
- Zsh with powerline10k theme
- Network lockdown via `init-firewall.sh` at container start

### Setup (one-time)

Copy the policy files to your host:
```bash
mkdir -p ~/.config/agent-sandbox/policies
cp docs/policy/examples/claude.yaml ~/.config/agent-sandbox/policies/claude.yaml
cp docs/policy/examples/claude-devcontainer.yaml ~/.config/agent-sandbox/policies/claude-vscode.yaml
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

### Customizing the Policy

Policy files live on the host at `~/.config/agent-sandbox/policies/`. The compose files mount the appropriate policy:

- CLI mode: `policies/claude.yaml`
- Devcontainer mode: `policies/claude-vscode.yaml`

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

The firewall (`init-firewall.sh`) verifies on startup that direct outbound is blocked and the host network is reachable.

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

## Target Platform

Primary: Colima on Apple Silicon (macOS). Should work on any Docker-compatible runtime.
