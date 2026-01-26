# Local Development of Agent Sandbox

This devcontainer is used for development of Agent Sandbox itself.

## Setup

### 1. Build local images

From the repo root on your host:

```bash
./images/build.sh
```

### 2. Set up policy files

Copy the policy files to your host config:

```bash
mkdir -p ~/.config/agent-sandbox/policies
cp docs/policy/examples/claude.yaml ~/.config/agent-sandbox/policies/claude.yaml
cp docs/policy/examples/claude-devcontainer.yaml ~/.config/agent-sandbox/policies/claude-vscode.yaml
```

### 3. Open in VS Code

- Command Palette > "Dev Containers: Reopen in Container"

## Files

- `docker-compose.yml` - Compose stack with proxy sidecar and agent container
- `devcontainer.json` - VS Code devcontainer config pointing to the compose file

## How It Works

The devcontainer runs as a Docker Compose stack with two containers:

1. **proxy** - mitmproxy with policy enforcement. Blocks requests to domains not on the allowlist.
2. **agent** - Development environment with Claude Code. All HTTP/HTTPS traffic routes through the proxy.

The agent container runs `init-firewall.sh` at startup which blocks all direct outbound traffic, forcing everything through the proxy.

## First-Time Setup

Claude Code needs OAuth authentication on first run. From your **host terminal**:

```bash
docker compose -f .devcontainer/docker-compose.yml ps  # find container name
docker exec -it <container-name> zsh -i -c 'claude'
```

Follow the OAuth flow, then `/exit`. Credentials persist in a Docker volume.

## Adding Allowed Domains

Edit your policy file at `~/.config/agent-sandbox/policies/claude-vscode.yaml`:

```yaml
services:
  - github
  - claude
  - vscode

domains:
  - your-new-domain.com  # Add here
```

Then restart the proxy:

```bash
docker compose -f .devcontainer/docker-compose.yml restart proxy
```

## Troubleshooting

**403 errors**: The domain is not in the allowlist. Check `~/.config/agent-sandbox/policies/claude-vscode.yaml`.

**Proxy health check fails**: Check proxy logs:
```bash
docker compose -f .devcontainer/docker-compose.yml logs proxy
```

**Policy file not found**: Make sure you copied the policy to `~/.config/agent-sandbox/policies/claude-vscode.yaml`.

**Claude auth issues**: Run auth from host terminal, not VS Code integrated terminal.
