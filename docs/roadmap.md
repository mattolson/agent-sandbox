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

## m4: Multi-agent support (done)

- Claude Code support (`cli/templates/claude/`)
- GitHub Copilot CLI support (`cli/templates/copilot/`)
- Remaining agents promoted to individual milestones (m7-m11)

## m5: CLI (done)

- `agentbox init` - interactive project setup (agent, mode, IDE, volumes, policy)
- `agentbox exec` - start or attach to the agent container
- `agentbox edit policy` - edit network policy, auto-restart proxy on save
- `agentbox edit compose` - open compose file in editor
- `agentbox bump` - pull latest images and pin to new digests
- `agentbox <command>` - pass-through to docker compose
- `agentbox destroy` - remove containers, volumes, and config
- `agentbox version` - show version info
- Docker-based CLI distribution (`ghcr.io/mattolson/agent-sandbox-cli`)
- Bash 3.2 compatibility (macOS default shell)

## m6: Deep customization (done)

- Shell-init hooks survive user .zshrc replacement
- Dotfiles support with recursive auto-symlinking
- Language stack installer scripts (python, node, go, rust)
- STACKS build arg for one-liner installation

## m7: [Codex](https://github.com/openai/codex) support (planned)

- agent-sandbox-codex image and templates
- OpenAI Codex CLI installation and configuration
- Network policy with Codex API domains

## m8: [Gemini CLI](https://github.com/google-gemini/gemini-cli) support (planned)

- agent-sandbox-gemini image and templates
- Google Gemini CLI installation and configuration
- Network policy with Gemini API domains

## m9: [Factory](https://github.com/Factory-AI/factory) support (planned)

- agent-sandbox-factory image and templates
- Factory agent installation and configuration
- Network policy with Factory API domains

## m10: [OpenCode](https://github.com/anomalyco/opencode) support (planned)

- agent-sandbox-opencode image and templates
- OpenCode installation and configuration
- Network policy with required API domains

## m11: [Pi](https://github.com/badlogic/pi-mono) support (planned)

- agent-sandbox-pi image and templates
- Pi agent installation and configuration
- Network policy with required API domains

## m12: Go CLI rewrite (planned)

- Rewrite agentbox CLI in Go using Cobra
- Single static binary distribution (replace Docker CLI image)
- Native YAML handling (drop yq dependency)
- Cross-compile for macOS (arm64, amd64) and Linux
- Port all existing commands with improved testing

## m13: Host credential service (planned)

- Host-side service bridging container to native credential store (macOS Keychain, Windows Credential Manager)
- No secrets stored on disk inside the container
- Container shim implements git credential helper protocol over HTTP to host service
- Works with any credential-aware tool (git, gh, etc.)
- Integrated into agentbox CLI lifecycle

## m14: Fine-grained proxy rules (planned)

- MITM inspection for HTTPS requests (path, method, query params visible)
- Nested path rules under domain entries in policy YAML
- Semantic service groupings (e.g., GitHub repo restrictions)
- Domain-only rules remain as fast-path (block at CONNECT)
- SIGHUP-based hot reload for policy changes

## m15: CLI monitoring and policy management (planned)

- Filtered log view for blocked requests
- Interactive unblock workflow
- Integration with hot reload for immediate policy updates
- UI approach TBD (filtered stream, TUI, or hybrid)
