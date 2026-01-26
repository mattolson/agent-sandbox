# 003: Separate Images Per Agent

## Status

Accepted

## Context

With interest in supporting multiple AI coding agents (Claude Code, GitHub Copilot CLI, Codex, Gemini CLI, OpenCode), we needed to decide how to package them:

1. **Single combo image** - All agents installed in one image
2. **Separate images per agent** - Each agent gets its own image extending a shared base
3. **Hybrid** - Separate images plus an optional combo image

## Decision

Build separate images for each agent, all extending a shared base image.

**Structure:**
```
images/
  base/           # Shared tooling, shell, firewall scripts
  proxy/          # mitmproxy sidecar (shared across all agents)
  agents/
    claude/       # Claude Code specific
    copilot/      # GitHub Copilot CLI specific
    codex/        # (future)
```

Each agent image:
- Extends `agent-sandbox-base`
- Installs only that agent's CLI tool
- Includes agent-specific default network policy
- Has its own version-check workflow for automated rebuilds

Users who want multiple agents can run multiple containers against the same repo, or build their own combo image locally.

## Rationale

**Why not a single combo image?**

- Different agents have different dependencies (Node.js versions, runtimes)
- Larger image size when you only need one agent
- Version management becomes complex (which agent triggered the rebuild?)
- Network policies differ per agent

**Why not provide an official combo image?**

- Maintenance burden (N agents × M combinations)
- Users can easily build their own if needed
- Most users will stick with one preferred agent

**Why a shared base image?**

- Consistent shell environment, tooling, and firewall behavior
- Single place to update common dependencies
- Reduces duplication across agent Dockerfiles

## Consequences

**Positive:**
- Smaller, focused images
- Clear versioning (image tag includes agent version)
- Independent release cycles per agent
- Simpler CI/CD (each agent has own version-check workflow)

**Negative:**
- Users wanting multiple agents need multiple containers or custom builds
- Some duplication in templates (docker-compose files are similar)

## References

- GitHub Issue: https://github.com/mattolson/agent-sandbox/issues/19
- Discussion between @mattolson and @jonmagic on 2026-01-25
