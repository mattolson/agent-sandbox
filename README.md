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

Two modes are supported with separate compose files:

| Mode | Compose file | Best for |
|------|-------------|----------|
| **Devcontainer** | `.devcontainer/docker-compose.yml` | VS Code, JetBrains IDEs |
| **CLI** | `docker-compose.yml` | Terminal users, non-devcontainer editors |

Both modes run a two-container stack: a proxy sidecar (mitmproxy) and the agent container. The separate compose files allow both to run simultaneously without container or volume name conflicts.

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need docker and docker-compose installed. So far we've tested with Colima + Docker Engine, but this should work with Docker Desktop for Mac or Podman as well. Instructions that follow are for Colima.

```bash
brew install colima docker docker-compose docker-buildx
colima start --cpu 4 --memory 8 --disk 60
```

Set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Set up network policy files

The network proxy reads its policy from a file on the host. Clone the repo and copy the examples:

```bash
git clone https://github.com/mattolson/agent-sandbox.git
mkdir -p ~/.config/agent-sandbox/policies
cp agent-sandbox/docs/policy/examples/* ~/.config/agent-sandbox/policies/
```

### 3. Copy template to your project

#### Option A: Devcontainer (VS Code / JetBrains)

```bash
cp -r agent-sandbox/templates/claude/.devcontainer /path/to/your/project/
```

**VS Code:**

- Install the Dev Containers extension
- Command Palette -> Dev Containers: Reopen in Container

**JetBrains (IntelliJ, PyCharm, WebStorm, etc.):**

- Open your project
- From the Remote Development menu, select "Dev Containers"
- Select the devcontainer configuration

#### Option B: Docker Compose (CLI)

```bash
cp agent-sandbox/templates/claude/docker-compose.yml /path/to/your/project/
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

Policy files live on the host at `~/.config/agent-sandbox/policies/`. The compose files mount the appropriate policy based on mode:

- CLI: `policies/claude.yaml`
- Devcontainer: `policies/claude-devcontainer.yaml`

To add project-specific domains, edit your policy file:

```yaml
services:
  - claude

domains:
  # Add your own
  - registry.npmjs.org
  - pypi.org
```

The policy file must live outside the workspace. If it were inside, the agent could modify it to allow exfiltration.

See [docs/policy/schema.md](./docs/policy/schema.md) for the full policy format reference.

Changes take effect on proxy restart: `docker compose restart proxy`

## Shell customization

You can inject custom shell configuration (aliases, environment variables, tool setup) by mounting scripts to `~/.config/agent-sandbox/shell.d/`. Any `*.sh` files in this directory are sourced when zsh starts.

### Setup

Create your customization directory and scripts on the host:

```bash
mkdir -p ~/.config/agent-sandbox/shell.d
```

Example script (`~/.config/agent-sandbox/shell.d/my-aliases.sh`):

```bash
# Custom aliases
alias ll='ls -la'
alias gs='git status'

# Environment variables
export EDITOR=vim
```

### Mounting the directory

Uncomment the shell.d mount in your compose file:

```yaml
# docker-compose.yml or .devcontainer/docker-compose.yml
volumes:
  - ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
```

### Using dotfiles

For more complex setups, mount your dotfiles directory and use a shell.d script to symlink them:

```yaml
# In your compose file
volumes:
  - ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
  - ${HOME}/.dotfiles:/home/dev/.dotfiles:ro
```

**`~/.config/agent-sandbox/shell.d/dotfiles.sh`:**
```bash
# Symlink dotfiles on shell start
[ -f ~/.dotfiles/.vimrc ] && ln -sf ~/.dotfiles/.vimrc ~/.vimrc
[ -f ~/.dotfiles/.gitconfig ] && ln -sf ~/.dotfiles/.gitconfig ~/.gitconfig
```

The mount is read-only, so the agent cannot modify your host configuration.

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
