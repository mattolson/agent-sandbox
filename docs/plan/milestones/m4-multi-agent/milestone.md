# m4-multi-agent

**Status: In Progress**

Add support for multiple AI coding agents beyond Claude Code. Each agent gets its own image extending a shared base, per [Decision 003](../../decisions/003-separate-images-per-agent.md).

## Motivation

Different AI coding agents have different strengths, dependencies, and API requirements. Users should be able to choose their preferred agent while maintaining the same sandbox security model:

- Network traffic routed through enforcing proxy
- Domain allowlist specific to each agent
- iptables firewall preventing proxy bypass
- Credentials persisted in Docker volumes

## Architecture

Per Decision 003, each agent gets its own image:

```
images/
  base/           # Shared tooling, shell, firewall scripts
  proxy/          # mitmproxy sidecar (shared across all agents)
  agents/
    claude/       # Claude Code (existing)
    copilot/      # GitHub Copilot CLI (m4.1)
    codex/        # (future)
    opencode/     # (future)
```

Each agent image:
- Extends `agent-sandbox-base`
- Installs only that agent's CLI tool
- Includes agent-specific default network policy
- Has its own version-check workflow for automated rebuilds

## Tasks

### m4.1-copilot-support (DONE)

Add GitHub Copilot CLI support.

- [x] Create `images/agents/copilot/` Dockerfile extending base
- [x] Add `copilot` service to proxy enforcer (API domains)
- [x] Create policy examples for Copilot (CLI and devcontainer modes)
- [x] Create `templates/copilot/` with compose files and README
- [x] Add build-copilot job to build-images.yml workflow
- [x] Add check-copilot-version.yml workflow for automated rebuilds
- [x] Update root README with multi-agent support
- [x] Update ROADMAP.md to reflect progress

### m4.2-codex-support (PLANNED)

Add OpenAI Codex CLI support.

- [ ] Research Codex CLI requirements and API domains
- [ ] Create `images/agents/codex/` Dockerfile
- [ ] Add `codex` service to proxy enforcer
- [ ] Create policy examples and templates
- [ ] Add CI workflows

### m4.3-opencode-support (PLANNED)

Add OpenCode support.

- [ ] Research OpenCode requirements
- [ ] Create `images/agents/opencode/` Dockerfile
- [ ] Add service to proxy enforcer
- [ ] Create policy examples and templates
- [ ] Add CI workflows

## Design Decisions

### Separate images vs combo image

See [Decision 003](../../decisions/003-separate-images-per-agent.md). Key points:

- Smaller, focused images
- Independent version/release cycles
- Clear which agent triggered a rebuild
- Users wanting multiple agents can run multiple containers

### Agent-specific policies

Each agent needs different API domains:
- Claude: `api.anthropic.com`, `*.claude.ai`
- Copilot: `api.githubcopilot.com`, `*.exp-tas.com`, etc.
- Codex: TBD

Policies are baked into agent images with a sensible default, but users can mount custom policies from the host.

## Definition of Done

- [x] At least one additional agent supported (Copilot)
- [ ] All supported agents have: image, policy, template, CI workflows
- [ ] Documentation covers multi-agent usage
- [ ] ROADMAP updated to reflect supported agents
