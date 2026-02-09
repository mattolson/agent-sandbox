# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Proxy-enforced domain allowlist (mitmproxy sidecar blocks non-allowed domains)
- Iptables firewall preventing direct outbound (all traffic must go through the proxy)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work on any Docker-compatible runtime.

## What it does

Creates a sandboxed environment for AI coding agents (Claude Code, GitHub Copilot CLI) that:

- Routes all HTTP/HTTPS traffic through an enforcing proxy sidecar
- Blocks requests to domains not on the allowlist (403 with domain name in response)
- Blocks all direct outbound via iptables (prevents bypassing the proxy)
- Runs as non-root user with limited sudo for firewall initialization in entrypoint
- Persists agent credentials and configuration in a Docker volume across container rebuilds

## Supported agents

| Agent | Template | Status |
|-------|----------|--------|
| [Claude Code](https://claude.ai/code) | `templates/claude/` | ✅ Stable |
| [GitHub Copilot CLI](https://github.com/github/copilot-cli) | `templates/copilot/` | 🧪 Preview |

## Runtime modes

Each template ships a single `.devcontainer/docker-compose.yml` that works for both devcontainer and CLI usage. A `.env` file at the project root sets `COMPOSE_FILE` so that `docker compose` commands work from the project directory without extra flags.

Both modes run a two-container stack: a proxy sidecar (mitmproxy) and the agent container.

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need docker and docker-compose installed. So far we've tested with Colima + Docker Engine, but this should work with Docker Desktop for Mac or Podman as well. Instructions that follow are for Colima.

```bash
brew install colima docker docker-compose docker-buildx
colima start --cpu 4 --memory 8 --disk 60
```

Set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Copy template to your project

```bash
git clone https://github.com/mattolson/agent-sandbox.git
cp -r agent-sandbox/templates/claude/.devcontainer /path/to/your/project/
cp agent-sandbox/templates/claude/.env /path/to/your/project/
```

The `.devcontainer/` directory contains the compose file, devcontainer config, and network policy. The `.env` file tells Docker Compose where to find the compose file.

### 3. Start the sandbox

**Devcontainer (VS Code / JetBrains):**

- VS Code: Install the Dev Containers extension, then Command Palette -> Dev Containers: Reopen in Container
- JetBrains: From the Remote Development menu, select "Dev Containers" and choose the configuration

**CLI (terminal):**

```bash
cd /path/to/your/project
docker compose up -d
docker compose exec agent zsh
```

### 4. Agent-specific setup

Follow the setup instructions specific to the agent image you are using:
- [Claude Code](./templates/claude/README.md)
- [GitHub Copilot](./templates/copilot/README.md)

## Network policy

Network enforcement has two layers:

1. **Proxy** (mitmproxy sidecar) - Enforces a domain allowlist at the HTTP/HTTPS level. Blocks requests to non-allowed domains with 403.
2. **Firewall** (iptables) - Blocks all direct outbound from the agent container. Only the Docker host network is reachable, which is where the proxy sidecar runs. This prevents applications from bypassing the proxy.

The proxy image ships with a default policy that blocks all traffic. You must mount a policy file to allow any outbound requests.

### How it works

The agent container has `HTTP_PROXY`/`HTTPS_PROXY` set to point at the proxy sidecar. The proxy runs a mitmproxy addon (`enforcer.py`) that checks every HTTP request and HTTPS CONNECT tunnel against the domain allowlist. Non-matching requests get a 403 response.

The agent's iptables firewall (`init-firewall.sh`) blocks all direct outbound except to the Docker bridge network. This means even if an application ignores the proxy env vars, it cannot reach the internet directly.

The proxy's CA certificate is shared via a Docker volume and automatically installed into the agent's system trust store at startup.

### Customizing the policy

The network policy lives in your project at `.devcontainer/policy.yaml`. This file is checked into version control and shared with your team.

To add project-specific domains, edit the policy file:

```yaml
services:
  - claude

domains:
  # Add your own
  - registry.npmjs.org
  - pypi.org
```

The `.devcontainer/` directory is mounted read-only inside the agent container, preventing the agent from modifying the policy, compose file, or devcontainer config. The proxy only reads the policy at startup, so changes require a human-initiated restart from the host.

See [docs/policy/schema.md](./docs/policy/schema.md) for the full policy format reference.

Changes take effect on proxy restart: `docker compose restart proxy`

## Shell customization

Two mechanisms for customizing the container environment, both mounted read-only from the host.

### Dotfiles

Mount your dotfiles directory to have them auto-linked into `$HOME` at container startup:

```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro
```

The entrypoint recursively walks `~/.dotfiles` and creates symlinks for each file at the corresponding `$HOME` path, creating intermediate directories as needed. For example, `.dotfiles/.config/git/config` becomes `~/.config/git/config`.

Protected paths (`.config/agent-sandbox`) are never overwritten. Docker bind mounts (like individually mounted config files) take precedence over dotfile symlinks.

### Shell.d scripts

Mount scripts into `~/.config/agent-sandbox/shell.d/` to inject aliases, environment variables, or tool setup. Any `*.sh` files are sourced when zsh starts, before `~/.zshrc`.

```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
```

Example (`~/.config/agent-sandbox/shell.d/my-aliases.sh`):

```bash
alias ll='ls -la'
alias gs='git status'
export EDITOR=vim
```

Shell.d scripts run from the system-level zshrc (`/etc/zsh/zshrc`), so dotfiles can include a custom `.zshrc` without breaking agent-sandbox functionality.

Both mounts are read-only. The agent cannot modify your host configuration. Uncomment the relevant volume lines in your compose file to enable either or both.

## Git configuration

Git operations can be run from the host or from inside the container.

### Option 1: Git from host (recommended)

Run git commands (clone, commit, push) from your host terminal. The agent writes code, you handle version control. No credential setup needed inside the container.

### Option 2: Git from container

If you want the agent to run git commands, some setup is required.

**SSH is blocked.** Port 22 is blocked to prevent SSH tunneling, which could bypass the proxy. The container automatically rewrites SSH URLs to HTTPS:

```
git@github.com:user/repo.git  ->  https://github.com/user/repo.git
```

**Credential setup.** To push or access private repos, authenticate with GitHub:

```bash
gh auth login
```

This stores a token in the container's Claude state volume (persists across rebuilds). The gh CLI configures git to use this token automatically.

**Alternative: Fine-grained PAT.** For tighter access control, create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to specific repositories, then:

```bash
gh auth login --with-token < token.txt
```

## Security

This project reduces risk but does not eliminate it. Local dev is inherently best-effort sandboxing.

Key principles:

- Minimal mounts: only the repo workspace + project-scoped agent state
- Prefer short-lived credentials (SSO/STS) and read-only IAM roles
- Firewall verification runs at every container start

### Git credentials

If you run `gh auth login` inside the container, the resulting OAuth token grants access to **all repositories** your GitHub account can access, not just the current project. The network allowlist limits where data can be sent, but an agent with this token could read or modify any of your repos on github.com.

To limit exposure:

- **Run git from the host** - No credentials in the container at all
- **Use a fine-grained PAT** - Scope the token to specific repositories
- **Use a separate GitHub account** - Isolate sandboxed work entirely

### IDE devcontainer

Operating as a devcontainer (VS Code or JetBrains) opens a channel to the IDE. Installing extensions can introduce risk.

### Security issues

If you find a sandbox escape or bypass:

- Open a GitHub Security Advisory (preferred), or
- Open an issue with minimal reproduction details

## Roadmap

See [docs/roadmap.md](./docs/roadmap.md) for planned features and milestones.

## Contributing

PRs welcome for:

- New agent support
- Improved network policies
- Documentation and examples

Please keep changes agent-agnostic where possible and compatible with Colima on macOS.

## License

[MIT License](./LICENSE)
