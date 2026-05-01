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

- Claude Code support
- GitHub Copilot CLI support
- Remaining agents promoted to individual milestones (m7, m9-m12)

## m5: Deep customization (done)

- Shell-init hooks survive user .zshrc replacement
- Dotfiles support with recursive auto-symlinking
- Language stack installer scripts (python, node, go, rust)
- STACKS build arg for one-liner installation

## m6: CLI (done)

- `agentbox init` - interactive project setup (project name, agent, mode, IDE)
- `agentbox exec` - start or attach to the agent container
- `agentbox edit policy` - edit network policy and reload configuration in proxy container
- `agentbox edit compose` - open compose file in editor
- `agentbox bump` - pull latest images and pin to new digests
- `agentbox <command>` - pass-through to docker compose
- `agentbox destroy` - remove containers, volumes, and config
- `agentbox version` - show version info
- Initial Docker-based CLI distribution (retired after the Go CLI cutover)
- Bash 3.2 compatibility (macOS default shell)

## m7: [Codex](https://github.com/openai/codex) support (done)

- agent-sandbox-codex image, CLI/devcontainer templates, and init/build integration
- OpenAI Codex CLI installation from GitHub releases with its internal sandbox disabled in-container
- Network policy, CI publishing, and daily version checks for Codex/OpenAI domains

## m8: Agent switching (done)

- `agentbox switch --agent <name>` shipped
- Per-agent state volumes are preserved when switching
- Layered user compose/policy customizations are preserved (shared + optional mode/agent overrides)
- Policy layers are merged at proxy runtime
- Runtime ownership split is explicit: CLI mode is agentbox-managed, devcontainer mode is IDE-managed
- Legacy single-file setups now fail with explicit upgrade guidance instead of automatic migration tooling

## m9: [Gemini CLI](https://github.com/google-gemini/gemini-cli) support (done)

- agent-sandbox-gemini image and templates
- Google Gemini CLI installation and configuration
- Network policy with Gemini API domains

## m10: [Factory](https://github.com/Factory-AI/factory) support (done)

- agent-sandbox-factory image and templates
- Factory agent installation and configuration
- Network policy with Factory API domains

## m11: [Pi](https://github.com/badlogic/pi-mono) support (done)

- agent-sandbox-pi image and templates
- Pi agent installation and configuration
- Network policy with required API domains

## m12: [OpenCode](https://github.com/anomalyco/opencode) support (done)

- agent-sandbox-opencode image and templates
- OpenCode installation and configuration
- Network policy with required API domains

## m13: Go CLI rewrite (done)

- Rewrite agentbox CLI in Go using Cobra
- GitHub Releases binaries are the install path
- Legacy Bash CLI, parity harness, and Docker CLI image distribution removed after cutover
- Native YAML handling (drop yq dependency)
- Cross-compile for macOS (arm64, amd64) and Linux
- Port all existing commands with improved testing

## m14: Fine-grained proxy rules (done)

- Request-aware policy rules for HTTP and HTTPS using scheme, method, path, and exact query matching
- Nested rule objects under `domains` entries with deterministic layered merge behavior and `merge_mode: replace`
- Semantic service catalog mappings, including repo-scoped GitHub API and Git smart-HTTP restrictions
- Domain-only rules remain backward-compatible and keep the CONNECT fast path
- `agentbox proxy reload` and `agentbox edit policy` hot-reload policy changes with last-known-good fallback

## m15: GitHub REST wrapper (planned)

- Repo-scoped GitHub wrapper using REST-only endpoints
- Keep repo identity visible in request URLs so m14 policies can constrain access to one repo
- Support a curated set of high-value GitHub workflows that fit REST plus URL-based policy matching
- Prefer a standalone binary if practical; Go plus `google/go-github` is the leading candidate
- Define and document the supported subset and explicitly exclude GraphQL-dependent `gh` flows
- Initial auth can reuse existing/manual token flows; tighter integration can come later

## m16: Proxy-side secret injection (planned)

- Make proxy injection the primary mechanism for HTTP-native credentials
- Store raw secret values in a host-only source and mount them into the proxy only
- Inject headers on matched outbound requests with leak-detection guardrails
- First rollout: git over HTTPS with repo-level scoping
- Evaluate env-token clients such as `gh` where placeholder substitution is sufficient

## m17: CLI monitoring and policy management (planned)

- Filtered log view for blocked requests
- Interactive unblock workflow
- Integration with hot reload for immediate policy updates
- UI approach TBD (filtered stream, TUI, or hybrid)

## m18: Host credential service (planned)

- Secondary credential path for flows that cannot be handled by proxy injection
- Host-side service bridging container to native credential store or helper backend
- Container shim implements a helper protocol for clients that must receive credentials locally
- Keep credentials off disk inside the container even when direct injection is not viable
- Integrated into agentbox CLI lifecycle
