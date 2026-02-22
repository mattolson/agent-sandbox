# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent Sandbox creates locked-down local sandboxes for running AI coding agents (Claude Code, Copilot, etc.) with minimal filesystem access and restricted outbound network. Enforcement uses two layers: an mitmproxy sidecar that enforces a domain allowlist at the HTTP/HTTPS level, and iptables rules that block all direct outbound to prevent bypassing the proxy.

**Note**: During development of this project, Claude Code operates inside a locked-down container using the docker compose method. This means git push/pull and other network operations outside the allowlist will fail from within the container. Handle git operations from the host.

## Development Environment

This project uses Docker Compose with a proxy sidecar. The compose file lives at `.agent-sandbox/docker-compose.yml` and the network policy at `.agent-sandbox/policy-cli-claude.yaml`.

The container runs Debian bookworm with:
- Non-root `dev` user (uid/gid 500)
- Zsh with minimal prompt
- Network lockdown via `init-firewall.sh` at container start
- SSH disabled (git must use HTTPS, URLs are auto-rewritten)

### Setup (one-time)

Build local images:
```bash
./images/build.sh
```

### Key Paths Inside Container
- `/workspace` - Your repo (bind mount)
- `/home/dev/.claude` - Claude Code state (named volume, persists per-project)
- `/commandhistory` - Bash/zsh history (named volume)

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

Available services and their domain allowlists are hardcoded in `images/proxy/addons/enforcer.py`. Adding a new service requires modifying `enforcer.py`. For one-off domains, use the `domains:` list instead.

### Customizing the Policy

For this project, the network policy lives at `.agent-sandbox/policy-cli-claude.yaml`. The `.agent-sandbox/` directory is mounted read-only inside the agent container, preventing the agent from modifying the policy. The proxy only reads the policy at startup.

To edit the policy in a user project: `agentbox edit policy`.

## Architecture

Four components:

1. **CLI** (`cli/`) - The `agentbox` command-line tool for initializing and managing sandboxed projects
2. **Images** (`images/`) - Base image, agent-specific images, proxy image, and CLI image
3. **Templates** (`cli/templates/`) - Per-agent, per-mode compose file and devcontainer templates
4. **Runtime** (`.agent-sandbox/docker-compose.yml`) - Docker Compose stack for developing this project

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

CLI tests use BATS. Run from the repo root:
```bash
cli/run-tests.bash
```

## Image Versioning

GitHub Actions builds images on:
- Push to main (when `images/**` or `cli/**` changes)
- Daily cron that checks for new Claude Code releases on npm (`check-claude-version.yml`)
- Daily cron that checks for new Copilot releases (`check-copilot-version.yml`)
- Manual workflow dispatch

Tags applied to agent images (e.g. `agent-sandbox-claude`):
- `latest`: Most recent build from main
- `sha-<commit>`: Git commit that triggered the build
- `claude-X.Y.Z` / `copilot-X.Y.Z`: Agent version installed in the image

To update images in a user project: `agentbox bump`.

## Known Workarounds

**HTTP/2 disabled for Go programs**: The compose files set `GODEBUG=http2client=0` to disable HTTP/2 in the gh CLI. This avoids header validation errors when requests pass through mitmproxy.

## Shell Customization

Shell initialization runs from `/etc/zsh/zshrc` (system-level), which sources `/etc/agent-sandbox/shell-init.sh` before `~/.zshrc`. This means shell.d scripts survive custom `.zshrc` replacements via dotfiles.

Drop scripts in `~/.config/agent-sandbox/shell.d/*.sh` on the host. They're sourced at shell startup (read-only mount). The shell-init chain is root-owned to prevent the agent from injecting commands.

## Dotfiles

Mount `~/.config/agent-sandbox/dotfiles` into the container and files are auto-symlinked into `$HOME` at startup. Protected paths (`.config/agent-sandbox`) are skipped. See `images/base/link-dotfiles.sh`.

## Language Stacks

Installer scripts at `/etc/agent-sandbox/stacks/` (python, node, go, rust). Not executed in published images. Users extend the image with a Dockerfile or use `STACKS="python,go:1.23"` when building via `build.sh`.

## Target Platform

Primary: Colima on Apple Silicon (macOS). Should work on any Docker-compatible runtime.
