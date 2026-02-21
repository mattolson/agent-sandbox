# Roadmap

Detailed project plan can be found in [plan/project.md](./plan/project.md) and related files.

## m1: Devcontainer template (done)

- Base + agent-specific images (`images/`)
- Policy YAML for configurable domain allowlists
- Reusable template (`templates/claude/`)
- Documentation for adding to other projects

## m2: Published images (done)

- Build and publish images to GitHub Container Registry
- Multi-platform support
- Pin images by digest for reproducibility

## m2.5: Shell customization (done)

- Mount custom shell scripts via `~/.config/agent-sandbox/shell.d/`
- Support for dotfiles directory mounting
- Read-only mounts to prevent agent modification

## m3: Proxy enforcement (done)

- mitmproxy sidecar for traffic logging and domain enforcement
- Log mode (`PROXY_MODE=log`) to observe what endpoints agents need
- Structured JSON logs for analysis
- Two-layer enforcement: proxy allowlist + iptables to prevent bypass
- SSH blocked, git over HTTPS only

## m4: Multi-agent support (in progress)

- [x] Claude Code support (`cli/templates/claude/`)
- [x] GitHub Copilot CLI support (`cli/templates/copilot/`)
- [ ] Gemini support
- [ ] Codex support
- [ ] OpenCode support

## m5: CLI (done)

- `agentbox init` - interactive project setup (agent, mode, IDE, volumes, policy)
- `agentbox exec` - start or attach to the agent container
- `agentbox policy` - edit network policy, auto-restart proxy on save
- `agentbox compose` - pass-through to docker compose
- `agentbox compose bump` - pull latest images and pin to new digests
- `agentbox compose edit` - open compose file in editor
- `agentbox clean` - remove containers, volumes, and config
- `agentbox version` - show version info
- Docker-based CLI distribution (`ghcr.io/mattolson/agent-sandbox-cli`)
- Bash 3.2 compatibility (macOS default shell)
