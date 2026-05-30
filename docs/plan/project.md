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

### m1-devcontainer-template (done)

Extract the current `.devcontainer/` into a reusable template that other projects can copy and configure.

**Goals:**
- Parameterize the devcontainer (agent choice, policy profile)
- Create the "minimal" template (iptables-based, no proxy)
- Document usage for new projects
- Test on a fresh project

**Out of scope:**
- Proxy-based template (m3)
- Pre-built images (m2)

### m2-images (done)

Build the image hierarchy so devcontainers use pre-built images instead of building from scratch.

**Goals:**
- Create agent-sandbox-base Dockerfile
- Create agent-sandbox-claude Dockerfile extending base
- Set up GitHub Actions to build and publish images
- Update devcontainer template to use published images
- Pin images by digest

**Dependencies:** m1 (template exists to update)

### m3-proxy (done)

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

### m4-multi-agent (done)

Initial multi-agent support. Claude Code and GitHub Copilot shipped. Remaining agents promoted to individual milestones (m7, m9-m12).

**Delivered:**
- agent-sandbox-claude image and templates
- agent-sandbox-copilot image and templates
- Agent-specific configuration in templates
- Documentation for adding new agents

**Dependencies:** m2 (image hierarchy established), m3 (proxy for endpoint discovery)

### m5-deep-customization (done)

Extend the customization story to support dotfiles, custom zshrc, and language stacks without forking Dockerfiles.

**Goals:**
- Shell-init hooks survive user .zshrc replacement (system-level sourcing via `/etc/zsh/zshrc`)
- First-class dotfiles support with recursive auto-symlinking at startup
- Language stack installer scripts shipped in base image (python, node, go, rust)
- STACKS build arg for one-liner stack installation via build.sh

**Dependencies:** m2.5 (shell customization established)

### m6-cli (done)

Create the `agentbox` CLI for managing sandbox configurations.

**Goals:**
- `agentbox init` - scaffold .devcontainer/ from template
- `agentbox bump` - update image digests to latest
- `agentbox edit policy` - manage allowlist domains

**Dependencies:** m1 (templates exist), m2 (images to reference)

### m7-codex (done)

Add OpenAI Codex CLI agent support.

**Dependencies:** m6 (CLI and templates established)

**Delivered:**
- Codex image, templates, and CLI integration shipped
- OpenAI/Codex proxy domains and CI version tracking added
- Codex setup and usage documentation added

### m8-agent-switching (done)

Add first-class, non-destructive agent switching so users can move between Claude, Codex, and Copilot without losing state or customizations.

**Goals:**
- Add `agentbox switch --agent <name>` with interactive prompts for missing values
- Preserve per-agent Docker volumes across switches
- Preserve user compose/policy customizations with managed vs user-owned layered boundaries
- Reduce policy duplication with shared project policy override plus optional mode/agent-specific overrides
- Merge layered policy at proxy runtime (single merge path), not via pre-generated artifacts
- Clarify runtime ownership split: CLI mode agentbox-managed, devcontainer mode IDE-managed
- Use explicit breaking-change upgrade guidance instead of automatic migration tooling

**Dependencies:** m6 (CLI), m7 (Codex), m4 (multi-agent foundations)

**Delivered:**
- `agentbox switch` with active-agent state and non-destructive layered runtime selection shipped
- Compose and policy ownership split into managed and user-owned layers under `.agent-sandbox/`
- Devcontainer flow reduced to an IDE shim over centralized runtime files
- Legacy single-file layouts now fail fast with an upgrade guide instead of silent fallback behavior

### m9-gemini (done)

Add Google Gemini CLI agent support.

**Dependencies:** m6 (CLI and templates established)

### m10-factory (done)

Add Factory agent support.

**Dependencies:** m6 (CLI and templates established)

### m11-pi (done)

Add Pi agent support.

**Dependencies:** m6 (CLI and templates established)

### m12-opencode (done)

Add OpenCode agent support.

**Dependencies:** m6 (CLI and templates established)

**Delivered:**
- OpenCode image, templates, and CLI integration shipped
- OpenCode proxy domains (opencode.ai, models.dev) and CI version tracking added
- Provider-agnostic setup documented (same pattern as Pi)

### m13-go-cli-rewrite (done)

Rewrite the `agentbox` CLI in Go using Cobra. Single static binary for easier distribution, testing, and feature development.

**Goals:**
- Port all existing commands (init, exec, edit, bump, destroy, version)
- Cobra-based command structure with proper argument parsing
- Native YAML handling (replace yq dependency)
- Cross-compile for macOS (arm64, amd64) and Linux
- Replace Docker CLI image distribution with binary releases

**Dependencies:** m6 (existing CLI defines the feature set to port)

**Delivered:**
- Go `agentbox` implementation now covers the current command surface
- GitHub Releases binaries replaced the old Bash distribution path
- Embedded Go templates are the only live template source tree
- Legacy Bash CLI, parity harness, and Docker CLI image distribution were removed after cutover

### m14-fine-grained-proxy (done)

Extend proxy enforcement beyond domain-level rules to support scheme, path, method, and exact query parameter
filtering.

**Goals:**
- Move HTTPS blocking decision from CONNECT to request handler (full MITM inspection)
- Policy format supports nested path rules under domain entries
- Service definitions support semantic groupings (e.g., GitHub repo restrictions)
- Backward-compatible: domain-only rules still work at CONNECT level as fast path
- SIGHUP-based hot reload for policy changes without dropping connections

**Dependencies:** m3 (proxy established)

**Delivered:**
- Request-aware policy rules for HTTP and HTTPS, with host-only policies preserved on the CONNECT fast path
- Deterministic layered policy rendering with canonical host records and `merge_mode: replace`
- Rich `services` mappings, including repo-scoped GitHub API and Git smart-HTTP expansion
- SIGHUP-based policy hot reload through `agentbox proxy reload` and `agentbox edit policy`
- Schema docs, examples, troubleshooting guidance, and proxy integration coverage

### m15-proxy-secret-injection (done)

Make the proxy the primary credential path for HTTP-native auth by keeping real secrets out of the agent container and injecting them into matched outbound requests.

**Goals:**
- Support direct matched-request credential injection for outbound HTTP headers
- Keep raw secret values in a host-only source mounted into the proxy only
- First supported rollout for git over HTTPS with repo-level scoping
- Use service catalog auth expansion for known services instead of pushing provider-specific behavior into the matcher
- Support fake client-visible compatibility values for env-token clients where the proxy can replace them with real
  credentials
- Support other HTTP-native auth patterns such as env-token clients where practical
- Add redacted audit logging for secret-backed requests

**Out of scope:**
- Browser or device-code OAuth flows
- Non-HTTP protocols
- Request body mutation
- Request, response, header, or URL scanning for leaked secret values
- Replacing every credential flow with proxy injection
- A complete scoped secret-management CLI
- A new live-update control plane beyond the existing policy reload path

**Dependencies:** m14 (request-phase MITM matching), m3 (proxy foundation)

### m16-hermes (done)

Add [Hermes](https://hermes-agent.nousresearch.com/docs/) (Nous Research's self-improving agent) as a supported agent
in Agent Sandbox. Users can initialize, run, and switch to Hermes via the standard `agentbox` workflow.

**Goals:**
- agent-sandbox-hermes Docker image extending the base image
- Install Hermes from its upstream shell installer with a pinned version, not `main`
- CLI templates (compose layer, devcontainer) following the established pattern for provider-agnostic agents
- Register Hermes in `internal/runtime/agents.go` and update Go tests
- Proxy service entry: Hermes-specific domains plus `hermes` in `KNOWN_AGENTS`
- `images/build.sh` support, build job in `build-images.yml`, daily version-check workflow
- Agent docs (`docs/agents/hermes.md`) and README support-matrix update
- Discovery first: Hermes's public docs do not enumerate auth env vars, API endpoints, telemetry, or sandbox-relevant
  flags, so the milestone opens with a discovery task before any code is written

**Out of scope:**
- Non-CLI Hermes integrations (Telegram, Discord, Slack, WhatsApp, Signal, etc.) — Hermes ships 20+ adapters; the
  sandbox only covers CLI mode
- Hermes's self-improving "skills" persistence behavior beyond ensuring the relevant state volume is mounted
- Provider-specific proxy domains; users add `claude`, `codex`, `openai`, `gemini`, or `openrouter` services to their
  policy based on which provider they point Hermes at

**Dependencies:** m13 (Go CLI defines the registration surface), m8 (agent switching), m3 (proxy)

### m17-provider-api-key-injection

Extend the `m15` proxy-side credential model from GitHub Git auth to model-provider API-key traffic, so current agents
can call supported provider APIs without the real API key being readable inside the agent container.

**Goals:**
- Add a generic raw-header transform for provider headers whose value is the secret itself
- Add service-catalog-owned auth expansion for OpenAI, Anthropic, and Gemini provider API patterns
- Support a generic renderer-owned fake env-var shim primitive, first used for clients that require `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, or `GEMINI_API_KEY` before making requests
- Cover Codex, Claude API-key mode, Gemini API-key mode, and provider-backed Pi/OpenCode flows where they use supported
  providers
- Keep OAuth, browser login, device-code, subscription-login, and local credential-helper flows out of this layer
- Document supported and unsupported agent/provider combinations clearly

**Out of scope:**
- Copilot and Factory primary auth unless a concrete API-key flow is identified during discovery
- OAuth, device-code, refresh-token, and browser-login flows
- Request-body mutation, response mutation, or scanning for leaked secret values
- Local delivery of real credentials into the agent container
- Arbitrary user-authored env exports that are not paired with catalog-owned proxy replacement rules
- Broad provider support beyond OpenAI, Anthropic, and Gemini

**Dependencies:** m15 (proxy-side secret injection), m14 (request-phase matching and transforms)

### m18-github-rest-wrapper

Provide an officially supported GitHub wrapper that uses REST-only endpoints so repo identity stays visible in request
URLs and can be constrained by `m14` policies.

**Goals:**
- Support a curated set of common, repo-scoped GitHub workflows using REST-only endpoints
- Keep repo identity explicit in URL paths so single-repo allowlists are practical under `m14`
- Prefer a thin wrapper over full parity with stock `gh`
- Prefer a standalone binary if practical; Go plus `google/go-github` is the leading candidate
- Define and document the supported subset plus unsupported GraphQL- or body-dependent flows
- Use `m15` proxy-side credential injection where practical instead of storing GitHub tokens in the agent container

**Out of scope:**
- Full parity with stock `gh`
- GraphQL-backed GitHub operations
- Re-implementing every GitHub workflow behind one generic wrapper surface

**Dependencies:** m14 (fine-grained proxy and repo/path-aware policy matching), m15 (primary HTTP credential path)

### m19-cli-monitoring

CLI tools for monitoring proxy activity and managing policy interactively.

**Goals:**
- Filtered log view showing only blocked requests
- Interactive unblock workflow (detect blocked request, generate rule, apply)
- Integration with hot-reload (m14) for immediate policy updates
- UI approach TBD during milestone planning (options: filtered log stream with prompts, TUI, or hybrid)

**Dependencies:** m13 (Go CLI), m14 (fine-grained proxy and hot reload)

### m20-host-credential-service

Add a narrower, secondary credential path for tools and auth flows that cannot be handled cleanly by proxy-side injection.

**Goals:**
- Host-side credential helper bridge for clients that must obtain a credential locally
- Support non-HTTP or helper-protocol-shaped auth workflows that `m15` cannot cover
- Keep credentials off disk inside the container even when the client must receive them
- Integrate the helper lifecycle with the Go CLI

**Dependencies:** m13 (Go CLI manages service lifecycle), m15 (primary proxy-based credential path defined first)

## Decisions

1. **Policy format**: YAML with domain-only granularity for m1-m4. Path/method filtering deferred to future work.
2. **CLI language**: Go. Single static binary, no runtime dependencies, easy cross-compilation.
3. **Registry**: GitHub Container Registry (ghcr.io). Free for public repos, native GitHub Actions integration.
4. **Proxy as enforcer**: iptables forces traffic through proxy sidecar, proxy enforces domain allowlist. See `decisions/001-proxy-as-enforcer.md`.
5. **No SSH**: Block SSH entirely, require git over HTTPS. Closes tunneling/exfiltration vector. See `decisions/002-no-ssh-https-only.md`.

## Open Questions

(None currently)

## Success Criteria

- A developer can add Agent Sandbox to their project in under 5 minutes
- Network lockdown is verifiable and auditable
- Images are reproducible and easy to update
- Documentation is clear enough for self-service adoption
