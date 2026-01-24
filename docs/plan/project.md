# Agent Sandbox Project Plan

## Vision

Make it safe and easy to run AI coding agents in "yolo mode" (auto-approve all actions) by providing locked-down local sandboxes with:
- Minimal filesystem access (repo + scoped state only)
- Restricted outbound network (allowlist-based)
- Reproducible environments (pinned images)

Target: open source project for the developer community, starting with Claude Code support.

## Current State

Two runtime modes are supported:

**Devcontainer mode** (`.devcontainer/`):
- For VS Code users
- Firewall initialized via `postStartCommand`
- Volumes and env vars in devcontainer.json

**Compose mode** (`docker-compose.yml`):
- For CLI/standalone users
- Firewall initialized via entrypoint script
- Same image, different initialization path

Both modes:
- Use iptables/ipset for network lockdown
- Run Claude Code in a Debian container
- Run as non-root user with limited sudo for firewall setup
- Block all outbound except allowlisted domains (GitHub, npm, Anthropic, etc.)

Image hierarchy established in `images/` (base + claude).

## Architecture Decisions

**Runtime modes:**
- **Devcontainer mode**: For VS Code users. Firewall initialized via `postStartCommand` (VS Code bypasses Docker entrypoints).
- **Compose mode**: For CLI/standalone users. Firewall initialized via entrypoint script with idempotent check.

Both modes use the same images; they differ only in how firewall initialization is triggered.

**Network enforcement approach:**
- Phase 1: iptables-based (simpler, already working)
- Phase 2: Add proxy option for request-level logging and centralized policy

**Image strategy:**
- Base image with common tools and hardening
- Agent-specific images extend base with only what that agent needs
- Entrypoint script handles firewall init for compose mode
- Pin by digest, update via PRs

## Milestones

### m1-devcontainer-template

Extract the current `.devcontainer/` into a reusable template that other projects can copy and configure.

**Goals:**
- Parameterize the devcontainer (agent choice, policy profile)
- Create the "minimal" template (iptables-based, no proxy)
- Document usage for new projects
- Test on a fresh project

**Out of scope:**
- Proxy-based template (m5)
- Pre-built images (m2)

### m2-images

Build the image hierarchy so devcontainers use pre-built images instead of building from scratch.

**Goals:**
- Create agent-sandbox-base Dockerfile
- Create agent-sandbox-claude Dockerfile extending base
- Set up GitHub Actions to build and publish images
- Update devcontainer template to use published images
- Pin images by digest

**Dependencies:** m1 (template exists to update)

### m3-proxy

Add proxy-based network observability to understand what endpoints agents need.

**Goals:**
- mitmproxy sidecar container with structured JSON logging
- Discovery mode (log everything, block nothing) to observe traffic
- Agent container routes through proxy via HTTP_PROXY env vars
- Tools to extract domain lists from logs
- Later: enforcement mode with allowlist

**Dependencies:** m2 (images established)

**Rationale:** Pulled forward from m5 because multi-agent support requires knowing what endpoints each agent needs. The proxy in discovery mode lets us observe traffic before defining policy.

### m4-multi-agent

Support additional coding agents beyond Claude Code.

**Goals:**
- agent-sandbox-opencode image
- agent-sandbox-codex image
- Agent-specific configuration in templates
- Documentation for adding new agents

**Dependencies:** m2 (image hierarchy established), m3 (proxy for endpoint discovery)

### m5-cli

Create the `agentbox` CLI for managing sandbox configurations.

**Goals:**
- `agentbox init` - scaffold .devcontainer/ from template
- `agentbox bump` - update image digests to latest
- `agentbox policy` - manage allowlist domains

**Dependencies:** m1 (templates exist), m2 (images to reference)

## Decisions

1. **Policy format**: YAML with domain-only granularity for m1-m4. Path/method filtering deferred to m5-proxy-runtime.
2. **CLI language**: Go. Single static binary, no runtime dependencies, easy cross-compilation.
3. **Registry**: GitHub Container Registry (ghcr.io). Free for public repos, native GitHub Actions integration.

## Open Questions

1. **Proxy choice**: Squid? Nginx? Custom Go proxy? Deferred to m5.

## Success Criteria

- A developer can add Agent Sandbox to their project in under 5 minutes
- Network lockdown is verifiable and auditable
- Images are reproducible and easy to update
- Documentation is clear enough for self-service adoption
