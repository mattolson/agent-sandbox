# Pi Coding Agent Sandbox Template

Run Pi Coding Agent in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

## Quick Start

### 1. Clone the agent-sandbox repo

```bash
git clone https://github.com/mattolson/agent-sandbox.git
```

### 2. Copy template to your project

```bash
cp -r agent-sandbox/templates/pi/.devcontainer /path/to/your/project/
cp agent-sandbox/templates/pi/.env /path/to/your/project/
```

The `.devcontainer/` directory contains the compose file, devcontainer config, and network policy. The `.env` file tells Docker Compose where to find the compose file.

### 3. Start the sandbox

**Devcontainer (VS Code / JetBrains):**

VS Code:
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

JetBrains (IntelliJ, PyCharm, WebStorm, etc.):
1. Open your project
2. From the Remote Development menu, select "Dev Containers"
3. Select the devcontainer configuration

**CLI (terminal):**

```bash
cd /path/to/your/project
docker compose up -d
docker compose exec agent zsh
```

### 4. Configure AI provider (first run only)

Pi supports multiple AI providers (Anthropic Claude, OpenAI, Google Gemini, etc.). You need to authenticate with at least one provider before using Pi.

Inside the container, run Pi and use the `/login` command:

```bash
pi
# Then in the Pi interface:
/login
```

Pi will guide you through:
1. Selecting your preferred AI provider
2. Authenticating (e.g., providing an API key or OAuth flow)
3. Optionally setting a default model

**Environment variables:**

You can also configure providers via environment variables. Add to the `agent` service in `docker-compose.yml`:

```yaml
environment:
  - ANTHROPIC_API_KEY=sk-ant-...
  - OPENAI_API_KEY=sk-...
```

**Network policy:**

Make sure your network policy (`.devcontainer/policy.yaml`) includes the service for your chosen provider:

- For Anthropic Claude: Add `claude` to the services list
- For OpenAI/ChatGPT: Add `codex` to the services list
- For Google Gemini: Add `gemini` to the services list
- For multiple providers: Add all that you need

See the Network Policy section below for details.

### 5. Use Pi

Inside the container:

```bash
pi
```

Pi will start in interactive mode. You can then issue coding tasks, ask questions, or use Pi's workflow commands.

Afterward, for CLI mode, stop the container:

```bash
docker compose down
```

## How It Works

Two containers run as a Docker Compose stack:

1. **proxy** (mitmproxy) - Enforces a domain allowlist. Blocks HTTP and HTTPS requests to non-allowed domains with 403. Logs all traffic as JSON to stdout.
2. **agent** (Pi CLI) - Your development environment. All HTTP/HTTPS traffic is routed through the proxy via `HTTP_PROXY`/`HTTPS_PROXY` env vars. An iptables firewall blocks any direct outbound connections, so traffic cannot bypass the proxy.

The proxy's CA certificate is automatically shared with the agent container and installed into the system trust store at startup.

## Network Policy

### Policy location

The network policy lives in your project at `.devcontainer/policy.yaml`. This file is checked into version control and shared with your team.

The `.devcontainer/` directory is mounted read-only inside the agent container, preventing the agent from modifying the policy, compose file, or devcontainer config. The proxy only reads the policy at startup, so even if the file were changed, it would not take effect until a human restarts the proxy from the host.

### Multi-provider support

Pi supports multiple AI providers. The default template includes the `codex` service (OpenAI), but you can customize this for your needs.

**To use Anthropic Claude:**

```yaml
services:
  - github
  - claude      # Anthropic Claude API
  - vscode
  - jetbrains
```

**To use Google Gemini:**

```yaml
services:
  - github
  - gemini      # Google Gemini API
  - vscode
  - jetbrains
```

**To use multiple providers:**

```yaml
services:
  - github
  - claude      # Anthropic Claude API
  - codex       # OpenAI API
  - gemini      # Google Gemini API
  - vscode
  - jetbrains
```

**For Azure OpenAI or custom endpoints:**

```yaml
services:
  - github
  - vscode
  - jetbrains

domains:
  - myorg.openai.azure.com
```

Restart the proxy after changes: `docker compose restart proxy`

### Policy format

```yaml
services:
  - github  # Expands to github.com, *.github.com, *.githubusercontent.com
  - claude  # Expands to Anthropic Claude API domains
  - codex   # Expands to OpenAI API domains
  - gemini  # Expands to Google Gemini API domains
  - vscode  # Expands to VS Code infrastructure domains

domains:
  - api.example.com        # Exact match
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

Uncomment the shell.d mount in the compose file.

## Language Stacks

The base image ships installer scripts for common language stacks. Use them in a custom Dockerfile or via the `STACKS` build arg.

### Custom Dockerfile

```dockerfile
FROM ghcr.io/mattolson/agent-sandbox-pi:latest
USER root
RUN /etc/agent-sandbox/stacks/python.sh
RUN /etc/agent-sandbox/stacks/go.sh 1.23.6
USER dev
```

Build and use your custom image:
```bash
docker build -t my-pi-sandbox .
# Update .devcontainer/docker-compose.yml to use image: my-pi-sandbox
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
image: ghcr.io/mattolson/agent-sandbox-pi@sha256:<digest>
image: ghcr.io/mattolson/agent-sandbox-proxy@sha256:<digest>
```

To find the current digest:

```bash
docker pull ghcr.io/mattolson/agent-sandbox-pi:latest
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/mattolson/agent-sandbox-pi:latest
```

To use locally-built images instead:

```bash
cd agent-sandbox && ./images/build.sh
# Then update the compose file to use:
#   image: agent-sandbox-pi:local
#   image: agent-sandbox-proxy:local
```

## Troubleshooting

### Proxy health check fails

The agent container waits for the proxy to be healthy before starting. If the proxy fails to start, check its logs:

```bash
docker compose logs proxy
```

### Pi cannot connect to AI provider

1. Verify your API key is set correctly (environment variable or Pi's `/login` command)
2. Check that the appropriate service is enabled in `.devcontainer/policy.yaml`
3. Restart the proxy: `docker compose restart proxy`
4. Verify from inside the container:
   ```bash
   # For Claude
   curl https://api.anthropic.com

   # For OpenAI
   curl https://api.openai.com

   # For Gemini
   curl https://generativelanguage.googleapis.com
   ```
