# Roadmap

Detailed project plan can be found in [docs/plan/project.md](./docs/plan/project.md) and related files.

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

## m3: Proxy observability

- mitmproxy sidecar for traffic logging
- Discovery mode to observe what endpoints agents need
- Structured JSON logs for analysis
- Foundation for request-level enforcement

## m4: Multi-agent support

- Codex support (first target)
- Support for OpenCode and other agents
- Agent-specific images and configuration

## m5: CLI

- `agentbox init` - scaffold devcontainer from template
- `agentbox bump` - update image digests
- `agentbox policy` - manage allowlist domains
