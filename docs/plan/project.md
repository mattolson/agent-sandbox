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

Replace iptables-based domain enforcement with proxy-based enforcement.

**Goals:**
- mitmproxy sidecar as the enforcement point for domain allowlists
- iptables as gatekeeper (forces all traffic through proxy)
- Structured JSON logging of all requests
- Discovery mode (log only) and enforcement mode (log + block)
- Block SSH, require git over HTTPS
- Devcontainer support via compose backend

**Dependencies:** m2 (images established)

**Rationale:** Proxy-based enforcement provides better observability, handles dynamic IPs, and offers a simpler mental model than IP-based iptables rules. iptables ensures the proxy cannot be bypassed.

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
- `agentbox edit policy` - manage allowlist domains

**Dependencies:** m1 (templates exist), m2 (images to reference)

### m6-deep-customization

Extend the customization story to support dotfiles, custom zshrc, and language stacks without forking Dockerfiles.

**Goals:**
- Shell-init hooks survive user .zshrc replacement (system-level sourcing via `/etc/zsh/zshrc`)
- First-class dotfiles support with recursive auto-symlinking at startup
- Language stack installer scripts shipped in base image (python, node, go, rust)
- STACKS build arg for one-liner stack installation via build.sh

**Dependencies:** m2.5 (shell customization established)

## Decisions

1. **Policy format**: YAML with domain-only granularity for m1-m4. Path/method filtering deferred to future work.
2. **CLI language**: Go. Single static binary, no runtime dependencies, easy cross-compilation.
3. **Registry**: GitHub Container Registry (ghcr.io). Free for public repos, native GitHub Actions integration.
4. **Proxy as enforcer**: iptables forces traffic through proxy sidecar, proxy enforces domain allowlist. See `decisions/001-proxy-as-enforcer.md`.
5. **No SSH**: Block SSH entirely, require git over HTTPS. Closes tunneling/exfiltration vector. See `decisions/002-no-ssh-https-only.md`.

## Open Questions

(None currently - proxy choice resolved as mitmproxy in m3)

## Success Criteria

- A developer can add Agent Sandbox to their project in under 5 minutes
- Network lockdown is verifiable and auditable
- Images are reproducible and easy to update
- Documentation is clear enough for self-service adoption
