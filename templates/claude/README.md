# Claude Code Sandbox Template

Run Claude Code in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

## Quick Start

### 1. Copy template to your project

```bash
git clone https://github.com/mattolson/agent-sandbox.git
```

#### Option A: VS Code Devcontainer

```bash
cp agent-sandbox/templates/claude/.devcontainer /path/to/your/project/
cp agent-sandbox/templates/claude/docker-compose.yml /path/to/your/project/
```

Then open in VS Code:
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

#### Option B: Docker Compose (CLI)

```bash
cp agent-sandbox/templates/claude/docker-compose.yml /path/to/your/project/
cd /path/to/your/project
docker compose up -d
docker compose exec agent zsh
```

### 2. Authenticate Claude (first run only)

From a host terminal (not VS Code integrated terminal):

```bash
docker ps  # find container name
docker exec -it <container-name> zsh -i -c 'claude'
```

Follow the OAuth flow, then `/exit`. Credentials persist in a Docker volume.

### 3. Use Claude Code

Inside the container:

```bash
claude
# or auto-approve mode:
yolo-claude
```

## How it works

Two containers run as a Docker Compose stack:

1. **proxy** (mitmproxy) - Enforces a domain allowlist. Blocks HTTP and HTTPS requests to non-allowed domains with 403. Logs all traffic as JSON to stdout.
2. **agent** (Claude Code) - Your development environment. All HTTP/HTTPS traffic is routed through the proxy via `HTTP_PROXY`/`HTTPS_PROXY` env vars. An iptables firewall blocks any direct outbound connections, so traffic cannot bypass the proxy.

The proxy's CA certificate is automatically shared with the agent container and installed into the system trust store at startup.

## Network Policy

The proxy image ships with a default policy that allows GitHub only. To add domains your project needs, mount a custom policy file from your host:

```bash
mkdir -p ~/.config/agent-sandbox
cat > ~/.config/agent-sandbox/policy.yaml << 'EOF'
services:
  - github

domains:
  - api.anthropic.com
  - sentry.io
  - statsig.anthropic.com
  - statsig.com
  - registry.npmjs.org
EOF
```

Then uncomment the mount in `docker-compose.yml`:

```yaml
volumes:
  # ...
  - ${HOME}/.config/agent-sandbox/policy.yaml:/etc/mitmproxy/policy.yaml:ro
```

Restart the proxy: `docker compose restart proxy`

The policy file must live outside the workspace. If it were inside, the agent could modify its own allowlist.

### Policy format

```yaml
services:
  - github  # Expands to github.com, *.github.com, *.githubusercontent.com

domains:
  - api.anthropic.com      # Exact match
  - "*.example.com"        # Wildcard suffix match
```

## Verifying the Sandbox

```bash
# Inside container:

# Should fail with 403 (blocked by proxy)
curl -s -o /dev/null -w "%{http_code}" https://example.com

# Should succeed (GitHub is allowed by default)
curl -s https://api.github.com/zen

# Direct outbound bypassing proxy should also fail (blocked by iptables)
curl --noproxy '*' --connect-timeout 3 https://example.com
```

## Shell Customization

Mount scripts into `~/.config/agent-sandbox/shell.d/` to customize your shell environment. Any `*.sh` files are sourced when zsh starts.

```bash
mkdir -p ~/.config/agent-sandbox/shell.d

cat > ~/.config/agent-sandbox/shell.d/my-aliases.sh << 'EOF'
alias ll='ls -la'
alias gs='git status'
EOF
```

Uncomment the shell.d mount in `docker-compose.yml`:

```yaml
- ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
```

## Image Versioning

By default, the template pulls `:latest`. For reproducibility, pin to a specific digest:

```yaml
# docker-compose.yml
image: ghcr.io/mattolson/agent-sandbox-claude@sha256:<digest>
image: ghcr.io/mattolson/agent-sandbox-proxy@sha256:<digest>
```

To find the current digest:

```bash
docker pull ghcr.io/mattolson/agent-sandbox-claude:latest
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/mattolson/agent-sandbox-claude:latest
```

To use locally-built images instead:

```bash
cd agent-sandbox && ./images/build.sh
# Then change docker-compose.yml to use:
#   image: agent-sandbox-claude:local
#   image: agent-sandbox-proxy:local
```

## Troubleshooting

### "Permission denied" mounting host files

The host Claude config mounts (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`) require these files to exist. Either create them or comment out those mounts.

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
