# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + project-scoped agent state)
- Restricted outbound network (iptables-based allowlist)
- Reproducible environments (Debian container with pinned dependencies)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work on any Docker-compatible runtime.

## What it does

The devcontainer in `.devcontainer/` creates a sandboxed environment for Claude Code:

- Blocks all outbound network traffic by default
- Allows only specific domains (GitHub, npm, Anthropic APIs, etc.)
- Runs as non-root user with limited sudo for firewall setup
- Persists Claude credentials in a Docker volume across container rebuilds

## Quick start (macOS + Colima + VS Code)

### 1. Install prerequisites

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8 --disk 60
```

If you previously used Docker Desktop, set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Add to your project

Copy the `.devcontainer` directory to your project:

```bash
# Clone agent-sandbox (or download just the .devcontainer folder)
git clone https://github.com/anthropics/agent-sandbox.git
cp -R agent-sandbox/.devcontainer /path/to/your/project/
```

Then open your project in VS Code:

- Install the Dev Containers extension
- Command Palette -> Dev Containers: Reopen in Container

### 3. Authenticate Claude Code (first time only)

From your **host terminal** (not the VS Code integrated terminal):

```bash
# Find your container name
docker ps

# Exec into it (name is typically the folder name with a suffix)
docker exec -it <container-name> zsh -i -c 'claude'
```

This triggers the OAuth flow:

1. Copy the URL and open it in your browser
2. Authorize the application
3. Paste the authorization code back into the terminal
4. Type `/exit` to close Claude

Credentials persist in the agent state volume. You only need to do this once.

### 4. Run Claude Code

From the VS Code integrated terminal inside the container:

```bash
claude
# or for auto-approve mode:
yolo-claude
```

## Network allowlist

The firewall (`init-firewall.sh`) blocks all outbound by default. Currently allowed:

- GitHub (api, web, git) - IPs fetched dynamically from api.github.com/meta
- registry.npmjs.org
- api.anthropic.com - for claude-code operations
- sentry.io, statsig.anthropic.com, statsig.com - for claude-code operations
- VS Code marketplace and update servers

To add a domain: edit `init-firewall.sh`, add to the domain loop, rebuild the container.

## How it works

At container startup, `init-firewall.sh`:

1. Creates an ipset for allowed IPs
2. Resolves each allowed domain and adds IPs to the set
3. Fetches GitHub's IP ranges from their meta API
4. Sets iptables rules to DROP all outbound except to the ipset
5. Verifies the firewall by testing that example.com is blocked and api.github.com works

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

### m1: Devcontainer template

Extract `.devcontainer/` into a reusable template with:

- Split Dockerfile into base + agent-specific images
- Policy YAML file for configurable domain allowlists
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
