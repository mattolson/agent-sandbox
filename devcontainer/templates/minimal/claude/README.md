# Claude Code Sandbox Template

Run Claude Code in a network-locked container with egress restricted to allowed domains only.

Images are published to GitHub Container Registry and pulled automatically.

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

## Shell Customization

Customize your shell environment by mounting scripts into the container.

### Adding aliases and functions

Create scripts in `~/.config/agent-sandbox/shell.d/`:

```bash
mkdir -p ~/.config/agent-sandbox/shell.d

cat > ~/.config/agent-sandbox/shell.d/my-aliases.sh << 'EOF'
alias ll='ls -la'
alias gs='git status'
alias gd='git diff'
EOF
```

Uncomment the shell.d mount in your config:

**devcontainer.json:**
```json
"source=${localEnv:HOME}/.config/agent-sandbox/shell.d,target=/home/dev/.config/agent-sandbox/shell.d,type=bind,readonly"
```

**docker-compose.yml:**
```yaml
- ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
```

### Using existing dotfiles

Mount your dotfiles directory and use a shell.d script to symlink them:

```bash
cat > ~/.config/agent-sandbox/shell.d/00-dotfiles.sh << 'EOF'
if [ -d ~/.dotfiles ]; then
  ln -sf ~/.dotfiles/.vimrc ~/.vimrc
  ln -sf ~/.dotfiles/.gitconfig ~/.gitconfig
  ln -sf ~/.dotfiles/.tmux.conf ~/.tmux.conf
  [ -f ~/.dotfiles/.aliases ] && source ~/.dotfiles/.aliases
fi
EOF
```

Then mount both directories:

**docker-compose.yml:**
```yaml
- ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
- ${HOME}/.dotfiles:/home/dev/.dotfiles:ro
```

### Overriding built-in aliases

The container includes `yolo-claude` and `yc` aliases. To override or remove them:

```bash
cat > ~/.config/agent-sandbox/shell.d/99-overrides.sh << 'EOF'
# Remove built-in aliases
unalias yolo-claude 2>/dev/null
unalias yc 2>/dev/null

# Or redefine with different flags
alias yolo-claude='claude --dangerously-skip-permissions --verbose'
EOF
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

## Image Versioning

By default, the template uses `:latest` which tracks the most recent build. For reproducibility, pin to a specific digest.

### Finding the current digest

```bash
docker pull ghcr.io/mattolson/agent-sandbox-claude:latest
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/mattolson/agent-sandbox-claude:latest
```

### Pinning in devcontainer

Edit `.devcontainer/Dockerfile`:

```dockerfile
ARG BASE_IMAGE=ghcr.io/mattolson/agent-sandbox-claude@sha256:<digest>
```

### Pinning in compose

Edit `docker-compose.yml`:

```yaml
image: ghcr.io/mattolson/agent-sandbox-claude@sha256:<digest>
```

### Local development

To use locally-built images instead of GHCR:

```bash
# Build images
git clone https://github.com/mattolson/agent-sandbox.git
cd agent-sandbox && ./images/build.sh

# Override in devcontainer (rebuild required)
# Edit .devcontainer/Dockerfile:
ARG BASE_IMAGE=agent-sandbox-claude:local

# Override in compose
# Edit docker-compose.yml:
image: agent-sandbox-claude:local
```
