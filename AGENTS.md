# Agent Instructions

This file provides guidance to agents when working with code in this repository.

## Project Overview

Agent Sandbox creates locked-down local sandboxes for running AI coding agents with minimal filesystem access and restricted outbound network. Enforcement uses two layers: an mitmproxy sidecar that enforces a domain allowlist at the HTTP/HTTPS level, and iptables rules that block all direct outbound to prevent bypassing the proxy.

Supported agents: `claude`, `codex`, `gemini`, `opencode`, `pi`, `copilot`, `factory`.

**Note**: During development of this project, the agent operates inside a locked-down container using the docker compose method. This means git push/pull and other network operations outside the allowlist will fail from within the container. Handle git operations from the host.

## Development Environment

This project uses layered Docker Compose files with a proxy sidecar. The managed CLI compose files live under `.agent-sandbox/compose/`, the active agent lives in `.agent-sandbox/active-target.env`, and the user-owned layered policy inputs live at `.agent-sandbox/policy/user.policy.yaml` plus `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`.

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
- `/home/dev/.codex` - Codex state (named volume, persists per-project)
- `/commandhistory` - Bash/zsh history (named volume)

### Templates vs Runtime Config

`internal/embeddata/templates/` contains the embedded templates used by `agentbox init` to generate per-project files. Editing a template affects all future `init` runs across all projects.

`.agent-sandbox/` at the repo root is the generated runtime config for developing this specific project. Editing files here only affects the local dev environment.

Do not confuse the two. When changing how `init` generates files, edit templates. When adjusting the local dev setup, edit `.agent-sandbox/`.

## Architecture

Three components:

1. **CLI** (`cmd/agentbox`, `internal/`) - The Go `agentbox` command-line tool plus its runtime, scaffold, docker, version, and embedded-template packages.
2. **Images** (`images/`) - Base image, agent-specific images, and proxy image.
3. **Runtime** (`.agent-sandbox/compose/*.yml`) - Layered Docker Compose stack for developing this project.

The base image contains the firewall script and common tools. Agent images extend it with agent-specific software. The proxy image runs mitmproxy with the policy enforcement addon.

### Image Directory Structure

```
images/
├── base/              # Base image (Dockerfile + shell scripts)
│   └── stacks/        # Language stack installers (python, node, go, rust)
├── agents/            # Agent-specific images
│   ├── claude/
│   ├── codex/
│   ├── copilot/
│   ├── factory/
│   └── gemini/
├── proxy/             # mitmproxy + policy enforcement
│   └── addons/        # enforcer.py (domain allowlist enforcement)
└── build.sh           # Image build script
```

### Proxy Internals

The proxy runs `mitmdump` (headless mitmproxy) with `enforcer.py` as an addon. At startup, `images/proxy/entrypoint.sh` invokes `images/proxy/render-policy` (Python) to merge the layered policy files into a single effective policy. `render-policy` merges the active agent's baseline policy with user and devcontainer overlays using `images/proxy/render-policy`.

The proxy Dockerfile installs `PyYAML`. The enforcer addon and render script are both Python.

Available services and their domain allowlists are hardcoded in `images/proxy/addons/enforcer.py`. Adding a new service requires modifying `enforcer.py`. For one-off domains, use the `domains:` list in policy files instead.

## CLI

### Code Conventions

The CLI is written in Go with Cobra entrypoints under `cmd/agentbox` and implementation packages under `internal/`.

Style rules:
- Format Go changes with `gofmt`
- Keep command handlers thin and push behavior into reusable packages such as `internal/runtime`, `internal/scaffold`, and `internal/docker`
- Treat `internal/embeddata/templates/` as the live template source of truth

### Package Structure

```
cmd/
└── agentbox/

internal/
├── cli/
├── docker/
├── embeddata/
├── runtime/
├── scaffold/
├── testutil/
└── version/
```

### Commands

`init`, `switch`, `exec`, `up`, `down`, `logs`, `compose`, `bump`, `edit` (`compose`|`policy`), `policy` (`config`|`render`), `destroy`, `version`, and `completion`.

See `docs/cli.md` for command documentation.

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

For layered CLI projects, the shared user-owned policy file is `.agent-sandbox/policy/user.policy.yaml`, and the active agent's additions live in `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`. The proxy renders the effective policy at startup from the active agent baseline plus those user-owned inputs. The `.agent-sandbox/` directory is mounted read-only inside the agent container, preventing the agent from modifying the policy.

To edit the policy in a user project: `agentbox edit policy`.
To inspect the rendered effective policy: `agentbox policy config`.

## Key Principles

- **Security-first**: Changes must maintain or improve security posture. Never bypass firewall restrictions without explicit user request.
- **Reproducibility**: Pin images by digest, not tag. Prefer explicit configs over defaults.
- **Agent-agnostic**: Core changes should support multiple agents. Agent-specific logic belongs in agent-specific images.
- **Policy-as-code**: Network policies should be reviewed like source code.

### Security-Critical Files

Changes to these files have outsized security impact and need extra scrutiny:
- `images/base/init-firewall.sh` - iptables rules that enforce network lockdown
- `images/proxy/addons/enforcer.py` - domain allowlist enforcement logic
- `images/proxy/render-policy` - policy merge logic (determines what gets allowed)
- `images/base/entrypoint.sh` - container startup (runs as root briefly)
- `images/base/install-proxy-ca.sh` - CA trust installation

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

CLI tests use Go. Run from the repo root:
```bash
go test ./...
```

## Image Versioning

GitHub Actions builds images on:
- Push to main (when `images/**` changes)
- Daily crons that check for new agent releases (`check-claude-version.yml`, `check-codex-version.yml`, `check-copilot-version.yml`, `check-gemini-version.yml`, `check-factory-version.yml`)
- Manual workflow dispatch

Tags applied to agent images (e.g. `agent-sandbox-claude`):
- `latest`: Most recent build from main
- `sha-<commit>`: Git commit that triggered the build
- `claude-X.Y.Z` / `copilot-X.Y.Z` / `codex-X.Y.Z` / etc.: Agent version installed in the image

To update images in a user project: `agentbox bump`.

## Adding a New Agent

See the `add-agent` skill at `.agents/skills/add-agent/SKILL.md`, or follow the pattern of an existing agent. A new agent requires:
- `images/agents/<name>/Dockerfile`
- `internal/embeddata/templates/<name>/` (CLI and devcontainer templates)
- `.github/workflows/check-<name>-version.yml`
- Entries in `images/proxy/render-policy` (`KNOWN_AGENTS`) and `images/proxy/addons/enforcer.py` (service domains)

## Known Workarounds

**HTTP/2 disabled for Go programs**: The compose files set `GODEBUG=http2client=0` to disable HTTP/2 in the gh CLI. This avoids header validation errors when requests pass through mitmproxy.

## Customization

For shell customization and dotfiles, see `docs/dotfiles.md`. For language stacks (Python, Node, Go, Rust), see `docs/stacks/`.

## Target Platform

Primary: Colima on Apple Silicon (macOS). Should work on any Docker-compatible runtime.
