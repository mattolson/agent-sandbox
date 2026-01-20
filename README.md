# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Restricted outbound network (iptables-based allowlist)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work on any Docker-compatible runtime.

## What it does

Creates a sandboxed environment for Claude Code that:

- Blocks all outbound network traffic by default
- Allows only specific domains (GitHub, npm, Anthropic APIs, etc.)
- Runs as non-root user with limited sudo for firewall setup
- Persists Claude credentials in a Docker volume across container rebuilds

## Runtime modes

Two modes are supported, using the same images:

| Mode | Best for | How to use |
|------|----------|------------|
| **Devcontainer** | VS Code users | Open project in Dev Container |
| **Compose** | CLI users, non-VS Code editors | `docker compose up -d && docker compose exec agent zsh` |

Both modes provide identical sandboxing. The difference is how the firewall gets initialized:
- **Devcontainer**: VS Code bypasses Docker entrypoints, so firewall runs via `postStartCommand`
- **Compose**: Firewall runs via the container's entrypoint script

Choose based on your editor preference. The quick start below covers both.

## Quick start (macOS + Colima)

### 1. Install prerequisites

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8 --disk 60
```

If you previously used Docker Desktop, set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Build the images

```bash
git clone https://github.com/mattolson/agent-sandbox.git
cd agent-sandbox
./images/build.sh
```

This builds `agent-sandbox-base:local` and `agent-sandbox-claude:local`.

### 3. Choose your mode

#### Option A: Devcontainer (VS Code)

```bash
cp -R agent-sandbox/devcontainer/templates/minimal/claude/.devcontainer /path/to/your/project/
```

Then open your project in VS Code:

- Install the Dev Containers extension
- Command Palette -> Dev Containers: Reopen in Container

#### Option B: Docker Compose (CLI)

```bash
cp agent-sandbox/devcontainer/templates/minimal/claude/docker-compose.yml /path/to/your/project/
cd /path/to/your/project
docker compose up -d
docker compose exec agent zsh
```

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
# or for auto-approve mode:
yolo-claude
```

For compose mode, stop the container when done:

```bash
docker compose down
```

## Network policy

The firewall blocks all outbound by default. Each image includes a default policy with the domains it needs:

| Image | Default policy |
|-------|----------------|
| **Base** | GitHub only |
| **Claude agent** | GitHub + Claude Code (api.anthropic.com, sentry.io, statsig.*) |
| **Devcontainer** | GitHub + Claude Code + VS Code (marketplace, updates, telemetry) |

This means everything works out of the box with no configuration.

### Customizing the policy

To add or remove domains, create a policy file at `~/.config/agent-sandbox/policy.yaml`:

```yaml
services:
  - github  # Dynamic IP fetch from api.github.com/meta

domains:
  # Claude Code
  - api.anthropic.com
  - sentry.io
  - statsig.anthropic.com
  - statsig.com

  # Add your own domains here
  - pypi.org
```

Then mount it in your config:

**devcontainer.json:**
```json
"mounts": [
  "source=${localEnv:HOME}/.config/agent-sandbox/policy.yaml,target=/etc/agent-sandbox/policy.yaml,type=bind,readonly"
]
```

**docker-compose.yml:**
```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/policy.yaml:/etc/agent-sandbox/policy.yaml:ro
```

The policy file must live outside the workspace. If it were inside, the agent could modify it and re-run the firewall to allow exfiltration.

Changes take effect on container restart.

## How it works

The firewall is initialized by `init-firewall.sh`, which:

1. Reads the policy file (`/etc/agent-sandbox/policy.yaml`)
2. Creates an ipset for allowed IPs
3. For each service (e.g., `github`), fetches IP ranges dynamically
4. For each domain, resolves via DNS and adds IPs to the set
5. Sets iptables rules to DROP all outbound except to the ipset
6. Verifies the firewall works (example.com blocked, at least one allowed endpoint reachable)

**Initialization differs by mode:**
- **Compose mode**: The entrypoint script runs `init-firewall.sh` automatically
- **Devcontainer mode**: VS Code bypasses entrypoints, so `postStartCommand` triggers initialization

The script is idempotent (checks for existing rules before running), so both paths work correctly.

The container runs as a non-root `dev` user with passwordless sudo only for the firewall setup commands.

## Security notes

This project reduces risk but does not eliminate it. Local dev is inherently best-effort sandboxing. For example, operating as a VS Code devcontainer opens up a channel to the IDE and installing extensions can introduce risk.

Key principles:

- Minimal mounts: only the repo workspace + project-scoped agent state
- Prefer short-lived credentials (SSO/STS) and read-only IAM roles
- Firewall verification runs at every container start
- Run long-lived agent sessions in tmux so VS Code reconnects don't kill the process

## Roadmap

Project plan can be seen in [docs/plan/project.md](./docs/plan/project.md) and related files, but here is the overview:

### m1: Devcontainer template (done)

- Base + agent-specific images (`images/`)
- Policy YAML for configurable domain allowlists
- Reusable template (`devcontainer/templates/minimal/claude/`)
- Documentation for adding to other projects

### m2: Published images

- Build and publish images to GitHub Container Registry
- Pin images by digest for reproducibility

### m3: CLI

- `agentbox init` - scaffold devcontainer from template
- `agentbox bump` - update image digests
- `agentbox policy` - manage allowlist domains

### m4: Multi-agent support

- Support for Codex, OpenCode, and other agents
- Agent-specific images and configuration

### m5: Proxy enforcement and logging

- Proxy-based network enforcement for request-level logging
- Docker Compose stack with structured audit logs

## Contributing

PRs welcome for:

- New agent support
- Improved network policies
- Documentation and examples

Please keep changes agent-agnostic where possible and compatible with Colima on macOS.

## Security issues

If you find a sandbox escape or bypass:

- Open a GitHub Security Advisory (preferred), or
- Open an issue with minimal reproduction details

## License

[MIT License](./LICENSE)
