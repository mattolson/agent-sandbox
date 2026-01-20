# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent Sandbox creates locked-down local sandboxes for running AI coding agents (Claude Code, Codex, etc.) with minimal filesystem access and restricted outbound network. It enforces network allowlisting via iptables/ipset rules at container startup.

**Note**: During development of this project, Claude Code operates inside a locked-down container using the docker compose method. This means git push/pull and other network operations outside the allowlist will fail from within the container. Handle git operations from the host.

## Development Environment

This project uses Docker Compose. The container runs Debian bookworm with:
- Non-root `dev` user (uid/gid 500)
- Zsh with powerline10k theme
- Network lockdown via `init-firewall.sh` at container start

### Key Paths Inside Container
- `/workspace` - Your repo (bind mount)
- `/home/dev/.claude` - Claude Code state (named volume, persists per-project)
- `/commandhistory` - Bash/zsh history (named volume)

### Useful Aliases
- `yolo-claude` (or `yc`) - Runs `claude --dangerously-skip-permissions` from /workspace

## Network Policy

The firewall blocks all outbound by default. Allowed destinations are defined in policy.yaml files.

### Policy Layering

Each image layer has its own policy file baked in at `/etc/agent-sandbox/policy.yaml`:

| Image | Policy | Allows |
|-------|--------|--------|
| base | `images/base/policy.yaml` | GitHub only |
| claude | `images/agents/claude/policy.yaml` | GitHub + Claude Code endpoints |
| devcontainer | `.devcontainer/policy.yaml` | GitHub + Claude Code + VS Code |

### Policy Format

```yaml
services:
  - github  # Special handling: fetches IPs from api.github.com/meta

domains:
  - api.anthropic.com
  - sentry.io
```

### Customizing the Policy

To override the baked-in policy, mount your own from the host filesystem:

```yaml
# docker-compose.yml
volumes:
  - ${HOME}/.config/agent-sandbox/policy.yaml:/etc/agent-sandbox/policy.yaml:ro
```

Policy must come from outside the workspace for security (prevents agent from modifying its own allowlist).

## Architecture

Three components:

1. **Images** (`images/`) - Base image + agent-specific images
2. **Runtime** (`docker-compose.yml`) - Docker Compose stack for standalone mode
3. **Devcontainer** (`.devcontainer/`) - VS Code devcontainer config

The base image contains the firewall script and common tools. Agent images extend it with agent-specific software and policies.

## Key Principles

- **Security-first**: Changes must maintain or improve security posture. Never bypass firewall restrictions without explicit user request.
- **Reproducibility**: Pin images by digest, not tag. Prefer explicit configs over defaults.
- **Agent-agnostic**: Core changes should support multiple agents. Agent-specific logic belongs in agent-specific images.
- **Policy-as-code**: Network policies should be reviewed like source code.

## Testing Firewall Changes

The `init-firewall.sh` script verifies the firewall after setup:
1. Confirms example.com is blocked
2. Confirms at least one allowed endpoint is reachable (GitHub API if enabled, otherwise first domain)

After modifying a policy file:
1. Rebuild the relevant image (`./images/build.sh`)
2. Restart container
3. Script auto-verifies on startup
4. Manually test your new allowed domain

## Target Platform

Primary: Colima on Apple Silicon (macOS). Should work on any Docker-compatible runtime.
