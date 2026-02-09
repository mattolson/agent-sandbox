# GitHub Copilot CLI Sandbox Template

Run GitHub Copilot CLI in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

## Quick Start

### 1. Clone the agent-sandbox repo

```bash
git clone https://github.com/mattolson/agent-sandbox.git
```

### 2. Set up policy files

The proxy requires policy files on the host. Copy the examples:

```bash
mkdir -p ~/.config/agent-sandbox/policies
cp agent-sandbox/docs/policy/examples/copilot* ~/.config/agent-sandbox/policies/
```

The compose files mount the appropriate policy:
- CLI mode uses `policies/copilot.yaml`
- Devcontainer mode uses `policies/copilot-devcontainer.yaml` (includes VS Code infrastructure domains)

### 3. Copy template to your project

#### Option A: Devcontainer (VS Code / JetBrains)

```bash
cp -r agent-sandbox/templates/copilot/.devcontainer /path/to/your/project/
```

**VS Code:**
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

**JetBrains (IntelliJ, PyCharm, WebStorm, etc.):**
1. Open your project
2. From the Remote Development menu, select "Dev Containers"
3. Select the devcontainer configuration

#### Option B: Docker Compose (CLI)

```bash
cp agent-sandbox/templates/copilot/docker-compose.yml /path/to/your/project/
cd /path/to/your/project
docker compose up -d
docker compose exec agent zsh
```

### 4. Authenticate Copilot (first run only)

From a host terminal (not VS Code integrated terminal):

```bash
docker compose ps  # find container name
docker exec -it <container-name> zsh -i -c 'copilot'
```

Follow the authentication flow using the `/login` command, then `/exit`. Credentials persist in a Docker volume.

### 5. Use Copilot CLI

Inside the container:

```bash
copilot
# or auto-approve mode:
copilot --yolo
```

## Two Modes

This template supports two usage modes with separate compose files:

| Mode | Compose file | Policy | Use case |
|------|-------------|--------|----------|
| **Devcontainer** | `.devcontainer/docker-compose.yml` | Requires host mount | VS Code, JetBrains IDEs |
| **CLI** | `docker-compose.yml` | Baked-in default | Terminal/headless usage |

The separate compose files allow both modes to run simultaneously without container or volume name conflicts.

## How It Works

Two containers run as a Docker Compose stack:

1. **proxy** (mitmproxy) - Enforces a domain allowlist. Blocks HTTP and HTTPS requests to non-allowed domains with 403. Logs all traffic as JSON to stdout.
2. **agent** (Copilot CLI) - Your development environment. All HTTP/HTTPS traffic is routed through the proxy via `HTTP_PROXY`/`HTTPS_PROXY` env vars. An iptables firewall blocks any direct outbound connections, so traffic cannot bypass the proxy.

The proxy's CA certificate is automatically shared with the agent container and installed into the system trust store at startup.

## Network Policy

### Policy location

Policy files live on the host at `~/.config/agent-sandbox/policies/`. The compose files mount the appropriate policy:
- CLI: `policies/copilot.yaml`
- Devcontainer: `policies/copilot-devcontainer.yaml`

Policy files must live outside the workspace. If they were inside, the agent could modify its own allowlist.

### Customizing the policy

Edit your policy file to add project-specific domains:

```yaml
services:
  - github
  - copilot
  - vscode  # Include for devcontainer mode

domains:
  # Add your own
  - registry.npmjs.org
  - pypi.org
```

Restart the proxy after changes: `docker compose restart proxy`

### Policy format

```yaml
services:
  - github  # Expands to github.com, *.github.com, *.githubusercontent.com
  - vscode  # Expands to VS Code infrastructure domains

domains:
  - api.githubcopilot.com  # Exact match
  - "*.example.com"        # Wildcard suffix match (also matches example.com)
```

## Verifying the Sandbox

```bash
# Inside container:

# Should fail with 403 (blocked by proxy)
curl -s -o /dev/null -w "%{http_code}" https://example.com

# Should succeed (GitHub is allowed)
curl -s https://api.github.com/zen

# Direct outbound bypassing proxy should also fail (blocked by iptables)
curl --noproxy '*' --connect-timeout 3 https://example.com
```

## Dotfiles

Mount your dotfiles directory to have them auto-linked into `$HOME` at container startup:

```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro
```

The entrypoint recursively walks `~/.dotfiles` and creates symlinks for each file at the corresponding `$HOME` path. Intermediate directories are created as needed.

For example, if your dotfiles contain:
```
.dotfiles/
  .zshrc
  .gitconfig
  .config/
    git/config
    starship.toml
```

The container will have:
- `~/.zshrc` -> `~/.dotfiles/.zshrc`
- `~/.gitconfig` -> `~/.dotfiles/.gitconfig`
- `~/.config/git/config` -> `~/.dotfiles/.config/git/config`
- `~/.config/starship.toml` -> `~/.dotfiles/.config/starship.toml`

Protected paths (`.config/agent-sandbox`) are never overwritten. Shell-init hooks are sourced from the system-level zshrc (`/etc/zsh/zshrc`), which runs before `~/.zshrc`, so your dotfiles can include a custom `.zshrc` without breaking agent-sandbox functionality.

## Shell Customization

Mount scripts into `~/.config/agent-sandbox/shell.d/` to customize your shell environment. Any `*.sh` files are sourced when zsh starts (before `~/.zshrc`).

```bash
mkdir -p ~/.config/agent-sandbox/shell.d

cat > ~/.config/agent-sandbox/shell.d/my-aliases.sh << 'EOF'
alias ll='ls -la'
alias gs='git status'
EOF
```

Uncomment the shell.d mount in the compose file you're using.

## Language Stacks

The base image ships installer scripts for common language stacks. Use them in a custom Dockerfile or via the `STACKS` build arg.

### Custom Dockerfile

```dockerfile
FROM ghcr.io/mattolson/agent-sandbox-copilot:latest
USER root
RUN /etc/agent-sandbox/stacks/python.sh
RUN /etc/agent-sandbox/stacks/go.sh 1.23.6
USER dev
```

Build and use your custom image:
```bash
docker build -t my-copilot-sandbox .
# Update docker-compose.yml to use image: my-copilot-sandbox
```

### STACKS build arg

If building from source, use the `STACKS` env var. Stacks are installed in the base image, so build with `all` or build base first:

```bash
STACKS="python,go:1.23.6" ./images/build.sh all
```

### Available stacks

| Stack | Script | Version arg | Default |
|-------|--------|-------------|---------|
| Python | `python.sh` | (ignored, uses apt) | System Python 3 |
| Node.js | `node.sh` | Major version | 22 |
| Go | `go.sh` | Full version | 1.23.6 |
| Rust | `rust.sh` | Toolchain | stable |

Each script handles both amd64 and arm64 architectures.

## Image Versioning

By default, the template pulls `:latest`. For reproducibility, pin to a specific digest:

```yaml
image: ghcr.io/mattolson/agent-sandbox-copilot@sha256:<digest>
image: ghcr.io/mattolson/agent-sandbox-proxy@sha256:<digest>
```

To find the current digest:

```bash
docker pull ghcr.io/mattolson/agent-sandbox-copilot:latest
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/mattolson/agent-sandbox-copilot:latest
```

To use locally-built images instead:

```bash
cd agent-sandbox && ./images/build.sh
# Then update the compose file to use:
#   image: agent-sandbox-copilot:local
#   image: agent-sandbox-proxy:local
```

## Troubleshooting

### Policy file not found

The policy files must exist on the host:

```bash
mkdir -p ~/.config/agent-sandbox/policies
cp agent-sandbox/docs/policy/examples/copilot.yaml ~/.config/agent-sandbox/policies/copilot.yaml
cp agent-sandbox/docs/policy/examples/copilot-devcontainer.yaml ~/.config/agent-sandbox/policies/copilot-devcontainer.yaml
```

### Proxy health check fails

The agent container waits for the proxy to be healthy before starting. If the proxy fails to start, check its logs:

```bash
docker compose logs proxy
```

### Container starts but network is unrestricted

Verify the firewall ran:

```bash
sudo iptables -S OUTPUT
```

Should show `-P OUTPUT DROP` followed by rules allowing only the host network. If not, check the entrypoint logs.
