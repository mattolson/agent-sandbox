# Claude Code Sandbox Template

Run Claude Code in a network-locked container with egress restricted to allowed domains only.

## Prerequisites

Build the base images (one-time setup):

```bash
git clone https://github.com/mattolson/agent-sandbox.git
cd agent-sandbox
./images/build.sh
```

This creates `agent-sandbox-base:local` and `agent-sandbox-claude:local`.

## Quick Start

### 1. Copy template to your project

#### Option A: VS Code Devcontainer

```bash
cp -R agent-sandbox/devcontainer/templates/minimal/claude/.devcontainer /path/to/your/project/
```

Then open in VS Code:
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

#### Option B: Docker Compose (CLI)

```bash
cp agent-sandbox/devcontainer/templates/minimal/claude/docker-compose.yml /path/to/your/project/
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

## Customizing the Network Policy

### Devcontainer mode

Edit `.devcontainer/policy.yaml` and rebuild the container:

```yaml
services:
  - github

domains:
  # Claude Code (required)
  - api.anthropic.com
  - sentry.io
  - statsig.anthropic.com
  - statsig.com

  # VS Code (required for devcontainer)
  - marketplace.visualstudio.com
  - mobile.events.data.microsoft.com
  - vscode.blob.core.windows.net
  - update.code.visualstudio.com

  # Add your domains here
  - registry.npmjs.org
  - pypi.org
```

Then: Command Palette > "Dev Containers: Rebuild Container"

### Compose mode

Create a policy file on your host:

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

Uncomment the mount in `docker-compose.yml`:

```yaml
volumes:
  # ...
  - ${HOME}/.config/agent-sandbox/policy.yaml:/etc/agent-sandbox/policy.yaml:ro
```

Then restart: `docker compose down && docker compose up -d`

## Verifying the Sandbox

The firewall verifies itself at startup. To manually test:

```bash
# Inside container:

# Should succeed (allowed)
curl -s https://api.github.com/zen

# Should fail immediately (blocked)
curl --connect-timeout 5 https://example.com
```

## Troubleshooting

### "Permission denied" mounting host files

The host claude config mounts (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`) require these files to exist. Either create them or comment out those mounts.

### Firewall verification fails

Check the policy.yaml syntax. The script exits non-zero if:
- Policy file is missing or malformed
- DNS resolution fails for a domain
- GitHub API is unreachable (if github service is enabled)

### Container starts but network is unrestricted

Verify the firewall ran:
```bash
sudo iptables -L -n
```

Should show DROP policies with an ipset match rule. If not, check `postStartCommand` (devcontainer) or entrypoint logs (compose).
