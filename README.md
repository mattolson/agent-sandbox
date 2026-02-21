# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Proxy-enforced domain allowlist (mitmproxy sidecar blocks non-allowed domains)
- Iptables firewall preventing direct outbound (all traffic must go through the proxy)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work with any Docker-compatible runtime.

## What it does

Creates a sandboxed environment for AI coding agents (currently Claude Code, GitHub Copilot CLI, but more to come) that:

- Routes all HTTP/HTTPS traffic through an enforcing proxy sidecar
- Blocks requests to domains not on the allowlist (403 with domain name in response)
- Blocks all direct outbound via iptables (prevents bypassing the proxy)
- Runs as non-root user with limited sudo only for firewall initialization in entrypoint
- Persists agent credentials and configuration in a Docker volume across container rebuilds

## Supported agents

| Agent | Status |
|-------|--------|
| [Claude Code](https://claude.ai/code) | ✅ Stable |
| [GitHub Copilot CLI](https://github.com/github/copilot-cli) | 🧪 Preview |

## Runtime modes

The sandbox is implemented as a Docker Compose project with a two-container stack: the agent container and a sidecar proxy (mitmproxy). There are two main ways to run this stack:

**CLI** mode (recommended) stores the docker-compose project in the `.agent-sandbox` directory.

**Devcontainer** mode stores the docker-compose project in the `.devcontainer` directory alongside the devcontainer.json configuration.

Both modes store the network proxy policy file in the `.agent-sandbox` directory.

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need docker and docker-compose installed. So far we've tested with Colima + Docker Engine, but this should work with Docker Desktop for Mac or Podman as well. Instructions that follow are for Colima.

```bash
# colima for VM, docker packages for running containers in VM, yq is a dependency for agentbox cli
brew install colima docker docker-compose docker-buildx yq
colima start --cpu 4 --memory 8 --disk 60
```

Set your [Docker credential helper](https://docs.docker.com/reference/cli/docker/login/#configure-the-credential-store) to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Install agent-sandbox CLI

The [CLI](cli/README.md) is a helper script and thin wrapper around docker-compose that simplifies the process of initializing and starting the sandbox.

#### Local install (recommended)

```bash
# Clone the repo
git clone https://github.com/mattolson/agent-sandbox.git

# Add agenbox bin directory to your path (add this to your .bashrc or .zshrc)
export PATH="$PWD/agent-sandbox/cli/bin:$PATH"
```

`yq` is required to edit compose files. Install with `brew install yq`.

#### Run through docker image

You can also run the cli through a published docker image if you don't want to install anything locally:

```bash
# Pull the image to local docker
docker pull ghcr.io/mattolson/agent-sandbox-cli

# Add to your .bashrc or .zshrc
alias agentbox='docker run --rm -it -v "/var/run/docker.sock:/var/run/docker.sock" -v"$PWD:$PWD" -w"$PWD" -e TERM -e HOME --network none ghcr.io/mattolson/agent-sandbox-cli'
```

Using the Docker image disables the editor integration (`vi` installed in the image will be used instead of your host editor).

The host environment variables will not be available inside the container, unless you forward them explicitly. This is important, because Docker Compose runs inside the container. `HOME` is already forwarded to handle common use cases.

The image runs as root, to avoid permission issues with the host Docker socket. On Colima file ownership is mapped automatically, on Linux you should add `--user` parameter accordingly.

### 3. Initialize the sandbox for your project

```bash
agentbox init
```

This prompts you to select the agent type and mode (CLI or devcontainer), then sets up the necessary configuration files and network policy.

### 4. Start the sandbox

**CLI:**

```bash
agentbox exec
```

**Devcontainer (VS Code / JetBrains):**

VS Code:
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

JetBrains (IntelliJ, PyCharm, WebStorm, etc.):
1. Open your project
2. From the Remote Development menu, select "Dev Containers"
3. Select the devcontainer configuration

### 5. Agent-specific setup

Follow the setup instructions specific to the agent image you are using:
- [Claude Code](docs/claude/README.md)
- [GitHub Copilot](docs/copilot/README.md)

## Network policy

Network enforcement has two layers:

1. **Proxy** (mitmproxy sidecar) - Enforces a domain allowlist at the HTTP/HTTPS level. Blocks requests to non-allowed domains with 403.
2. **Firewall** (iptables) - Blocks all direct outbound from the agent container. Only the Docker host network is reachable, which is where the proxy sidecar runs. This prevents applications from bypassing the proxy.

The proxy image ships with a default policy that blocks all traffic. You must mount a policy file to allow any outbound requests. `agentbox init` will set this up for you.

### How it works

The agent container has `HTTP_PROXY`/`HTTPS_PROXY` set to point at the proxy sidecar. The proxy runs a mitmproxy addon (`enforcer.py`) that checks every HTTP request and HTTPS CONNECT tunnel against the domain allowlist. Non-matching requests get a 403 response.

The agent's iptables firewall (`init-firewall.sh`) blocks all direct outbound except to the Docker bridge network. This means even if an application ignores the proxy env vars, it cannot reach the internet directly.

The proxy's CA certificate is shared via a Docker volume and automatically installed into the agent's system trust store at startup.

### Customizing the policy

The network policy lives in your project in the `.agent-sandbox` directory. This file can be checked into version control and shared with your team.

To edit the policy file:

```bash
agentbox policy
```

This opens the network policy file in your editor. If you save changes, the proxy service will automatically restart to apply the new policy.

Example policy:

```yaml
services:
  - claude

domains:
  # Add your own
  - registry.npmjs.org
  - pypi.org
```

The `.agent-sandbox` directory is mounted read-only inside the agent container, preventing the agent from modifying the policy. The proxy reads the policy at startup, so changes require a restart from the host.

See [docs/policy/schema.md](./docs/policy/schema.md) for the full policy format reference.

## Dotfiles Support

You can optionally mount your dotfiles directory and have them auto-linked into `$HOME` at container startup:

```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro
```

The entrypoint recursively walks `/home/dev/.dotfiles` and creates symlinks for each file at the corresponding `$HOME` path. Intermediate directories are created as needed.

For example, if your dotfiles contain:
```
.dotfiles/
  .zshrc
  .gitconfig
  .claude/
    CLAUDE.md
    settings.json
  .config/
    git/config
    starship.toml
```

The container will have:
- `~/.zshrc` -> `~/.dotfiles/.zshrc`
- `~/.gitconfig` -> `~/.dotfiles/.gitconfig`
- `~/.claude/CLAUDE.md` -> `~/.dotfiles/.claude/CLAUDE.md`
- `~/.claude/settings.json` -> `~/.dotfiles/.claude/settings.json`
- `~/.config/git/config` -> `~/.dotfiles/.config/git/config`
- `~/.config/starship.toml` -> `~/.dotfiles/.config/starship.toml`

Docker bind mounts (like individually mounted `CLAUDE.md`) take precedence over dotfile symlinks.

## Shell Customization

You can also optionally mount scripts from `~/.config/agent-sandbox/shell.d/` to customize your shell environment. Any `*.sh` files are sourced when zsh starts.

```bash
mkdir -p ~/.config/agent-sandbox/shell.d

cat > ~/.config/agent-sandbox/shell.d/my-aliases.sh << 'EOF'
alias ll='ls -la'
alias gs='git status'
EOF
```

The `agentbox init` command prompts whether to enable shell customizations when setting up your project and will set up the volume mount.

shell.d scripts are sourced from the system-level zshrc (`/etc/zsh/zshrc`), which runs before `~/.zshrc`. This means your dotfiles can include a custom `.zshrc` without breaking this integration.

## Git configuration

Git operations can be run from the host or from inside the container.

### Option 1: Git from host (recommended)

Run git commands (clone, commit, push) from your host terminal. The agent writes code, you handle version control. No credential setup needed inside the container.

### Option 2: Git from container

If you want the agent to run git commands, some setup is required.

**SSH is blocked.** Port 22 is blocked to prevent SSH tunneling, which could bypass the proxy. The container automatically rewrites SSH URLs to HTTPS:

```
git@github.com:user/repo.git -> https://github.com/user/repo.git
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

## Extending with language stacks

The base image ships installer scripts for common language stacks. Extend the agent image with a custom Dockerfile:

```dockerfile
FROM ghcr.io/mattolson/agent-sandbox-claude:latest
USER root
RUN /etc/agent-sandbox/stacks/python.sh
RUN /etc/agent-sandbox/stacks/go.sh 1.23.6
USER dev
```

Build and use your custom image:
```bash
docker build -t my-custom-sandbox .
agentbox compose edit
# Update the agent service image to: my-custom-sandbox
```

Available stacks:

| Stack | Script | Version arg | Default |
|-------|--------|-------------|---------|
| Python | `python.sh` | (ignored, uses apt) | System Python 3 |
| Node.js | `node.sh` | Major version | 22 |
| Go | `go.sh` | Full version | 1.23.6 |
| Rust | `rust.sh` | Toolchain | stable |

Each script handles both amd64 and arm64 architectures.

Alternatively, if building from source, use the `STACKS` env var:

```bash
STACKS="python,go:1.23.6" ./images/build.sh all
```

## Image Versioning

The `agentbox init` command automatically pulls the latest images and pins the compose file to sha digests for reproducibility.

To update to newer image versions later:

```bash
agentbox compose bump
```

This pulls the newest versions and updates the compose file with the new sha digests.

To use locally-built images instead:

```bash
./images/build.sh
agentbox compose edit
# Update the images to use:
#   agent service: agent-sandbox-claude:local
#   proxy service: agent-sandbox-proxy:local
```

## Security

This project reduces risk but does not eliminate it. Local dev is inherently best-effort sandboxing.

Key principles:

- Minimal mounts: only the repo workspace + project-scoped agent state
- Network egress is tightly controlled through sidecar proxy with default deny policy
- Firewall verification runs at every container start

### Git credentials

If you run `gh auth login` inside the container, the resulting OAuth token grants access to **all repositories** your GitHub account can access, not just the current project. The network allowlist limits where data can be sent, but an agent with this token could read or modify any of your repos on github.com.

To limit exposure:

- **Run git from the host** - No credentials in the container at all
- **Use a fine-grained PAT** - Scope the token to specific repositories
- **Use a separate GitHub account** - Isolate sandboxed work entirely

### IDE devcontainer

Operating as a devcontainer (VS Code or JetBrains) opens a channel to the IDE. Installing IDE extensions can [introduce risk](https://blog.theredguild.org/leveraging-vscode-internals-to-escape-containers/). For tighter security, we recommend running in CLI mode (local docker compose and terminal operations, rather than IDE extensions).

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
