# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Proxy-enforced domain allowlist (mitmproxy sidecar blocks non-allowed domains)
- Iptables firewall preventing direct outbound (all traffic must go through the proxy)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work on any Docker-compatible runtime.

## What it does

Creates a sandboxed environment for Claude Code that:

- Routes all HTTP/HTTPS traffic through an enforcing proxy sidecar
- Blocks requests to domains not on the allowlist (403 with domain name in response)
- Blocks all direct outbound via iptables (prevents bypassing the proxy)
- Runs as non-root user with limited sudo for firewall initialization in entrypoint
- Persists Claude credentials and configuration in a Docker volume across container rebuilds

## Runtime modes

Two modes are supported with separate compose files:

| Mode | Compose file | Best for |
|------|-------------|----------|
| **Devcontainer** | `.devcontainer/docker-compose.yml` | VS Code, JetBrains IDEs |
| **CLI** | `docker-compose.yml` | Terminal users, non-devcontainer editors |

Both modes run a two-container stack: a proxy sidecar (mitmproxy) and the agent container. The separate compose files allow both to run simultaneously without container or volume name conflicts.

JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.) support devcontainers through the same `.devcontainer/` configuration. Open your project and select "Dev Containers" from the remote development options.

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need docker and docker-compose installed. So far we've only tested with Colima + Docker Engine, but this should work with Docker Desktop for Mac or Podman as well. Instructions that follow are for Colima.

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8 --disk 60
```

If you previously used Docker Desktop, set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Set up policy files

The proxy requires policy files on the host. Clone the repo and copy the examples:

```bash
git clone https://github.com/mattolson/agent-sandbox.git
mkdir -p ~/.config/agent-sandbox/policies
cp agent-sandbox/docs/policy/examples/claude.yaml ~/.config/agent-sandbox/policies/claude.yaml
cp agent-sandbox/docs/policy/examples/claude-devcontainer.yaml ~/.config/agent-sandbox/policies/claude-vscode.yaml
```

The compose files mount the appropriate policy:
- CLI mode uses `policies/claude.yaml`
- Devcontainer mode uses `policies/claude-vscode.yaml` (includes VS Code infrastructure domains)

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

Note: CLI mode requires the policy file at `~/.config/agent-sandbox/policies/claude.yaml`.

### 4. Authenticate Claude Code (first time only)

From your **host terminal** (not the VS Code integrated terminal):

```bash
# Find your container name
docker ps

# Exec into it
docker exec -it <container-name> zsh -i -c 'claude'
```

This triggers the OAuth flow:

1. Copy the URL and open it in your browser
2. Authorize the application
3. Paste the authorization code back into the terminal
4. Type `/exit` to close Claude

Credentials persist in a Docker volume. You only need to do this once per project.

### 5. Run Claude Code

From inside the container:

```bash
claude
# or as a shortcut for `claude --dangerously-skip-permissions`:
yolo-claude
```

For compose mode, stop the container when done:

```bash
docker compose down
```

## Claude Code: Terminal vs IDE extension

You can run Claude Code two ways inside the sandbox:

| Mode | How to start | IDE support |
|------|--------------|-------------|
| **Terminal** | Run `claude` in the integrated terminal | VS Code, JetBrains |
| **IDE extension** | Install Claude Code extension | VS Code only |

Both modes work with the sandbox. The proxy and firewall apply equally because both binaries run inside the container and respect the `HTTP_PROXY` environment variable.

**Shared configuration.** Both modes use the same Claude credentials and settings stored in the Docker volume (`~/.claude`). You can switch between terminal and extension freely. Authenticate once in either mode and both will work.

**Feature differences.** The IDE extension provides tighter editor integration (inline suggestions, chat panel). The terminal provides the full CLI feature set. Use whichever fits your workflow, or both.

**First-time setup with extension.** If you start fresh with the extension (no prior authentication), the extension will prompt you to authenticate through its UI. This works the same as the terminal OAuth flow.

**Connecting terminal to IDE.** Running `/ide` in the terminal Claude session shows the connection status to VS Code. When connected, Claude can interact with the editor directly.

**JetBrains users.** Use the terminal to run `claude` directly. The Claude Code JetBrains plugin does not work with devcontainers. See [Known issues](#known-issues) for details.

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
- Devcontainer: `policies/claude-vscode.yaml`

To add project-specific domains, edit your policy file:

```yaml
services:
  - github
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

## Known issues

### JetBrains Claude Code plugin not supported

The Claude Code plugin for JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.) does not work with devcontainers. Use the terminal to run `claude` instead.

**Why it doesn't work:** JetBrains runs the Claude plugin in the "frontend" (thin client on your host machine), while Claude Code runs inside the container. The plugin communicates with Claude via lock files and websockets, but these mechanisms assume both are on the same machine. The plugin writes to `~/.claude/ide/` on the host, but Claude looks for it at `/home/dev/.claude/ide/` in the container. Even if you mount the directory, the websocket connection from container to host would require additional network configuration.

**Workaround:** Run `claude` in the JetBrains integrated terminal. The terminal connects to the container, so Claude runs inside the sandbox with full network restrictions. You get the CLI experience but not the native IDE panel.

This is a limitation of the JetBrains plugin architecture, not something we can fix in the sandbox.

### VS Code extension may fail on first install

The Claude Code VS Code extension sometimes fails to install on first container startup because the proxy isn't fully ready. VS Code retries automatically, and the extension typically installs successfully on the second attempt. Check the Extensions panel if Claude doesn't appear immediately.

## Roadmap

See [ROADMAP.md](./ROADMAP.md) for planned features and milestones.

## Contributing

PRs welcome for:

- New agent support
- Improved network policies
- Documentation and examples

Please keep changes agent-agnostic where possible and compatible with Colima on macOS.

## License

[MIT License](./LICENSE)
