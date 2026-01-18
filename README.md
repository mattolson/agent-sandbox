# Agent Sandbox

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (only your repo + optional per-project state)
- Restricted outbound network (allowlist via an egress proxy)
- Structured security logs (every outbound request is logged)
- Reproducible environments (base image + agent-specific images, pinned by digest)

This project should work for local development against any docker-compatible runtime, but is currently focused on supporting [Colima](https://github.com/abiosoft/colima) on Apple Silicon.

## Goals

- Make it easy to run coding agents (Claude Code, Codex, etc.) in yolo mode with no fear
- Provide a reusable, team-friendly devcontainer setup
- Enforce outbound allowlists through a single choke point (proxy) with logs
- Keep agent runtimes reproducible and easy to update
- Stay editor-agnostic: VS Code devcontainers are supported, but not required

Non-goals (for now):

- Perfect "unbreakable" isolation (local dev is inherently a best-effort sandbox)
- Full MITM / deep packet inspection

## Architecture

Agent Sandbox is built from three reusable pieces:

1. Images
   - agent-sandbox-base: common dev tools + hardening defaults
   - agent-\* images: add a specific agent (e.g., agent-claude, agent-codex)

2. Runtime (locked-down network + logs)
   - Docker Compose stack: agent + proxy
   - The agent container has no direct egress; all outbound traffic goes through the proxy
   - Proxy enforces an allowlist and emits structured logs

3. Devcontainer templates
   - Reusable .devcontainer/ scaffolding for projects
   - Minimal per-project config: choose an agent image + policy profile

### The sandbox contract

Inside the agent container:

- Workspace: /workspace (your repo, writable, expected to be a git repository)
- Agent state: /agent-state (project-scoped, writable)
- Network: outbound allowed only via proxy (HTTP(S)\_PROXY)

## Quick start (macOS + Colima + VS Code devcontainers)

### 1. Install Colima + Docker CLI

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8 --disk 60
```

If you previously used Docker Desktop, set your Docker credential helper to `osxkeychain` (not `desktop`) in `~/.docker/config.json`.

### 2. Add agent sandbox to a project

From your project root:

```bash
cp -R path/to/agent-sandbox/devcontainer/templates/proxy-locked/.devcontainer .
```

Or use the minimal template if you do not want the proxy yet:

```bash
cp -R path/to/agent-sandbox/devcontainer/templates/minimal/.devcontainer .
```

### 3. Open in devcontainer

In VS Code:

- Install the Dev Containers extension
- Command Palette -> Dev Containers: Reopen in Container

### 4. Authenticate Claude Code (first time only)

On first run, Claude Code needs to authenticate. From your **host terminal** (not VS Code):

```bash
docker exec -it <container-name> zsh -i -c 'claude'
```

This triggers the onboarding flow (which includes OAuth login):

1. Copy the OAuth URL and open it in your browser
2. Authorize the application
3. Paste the authorization code back into the terminal
4. Type `/exit` to close Claude

Credentials are stored in the container's `.claude` volume and persist across restarts. You only need to do this once per devcontainer.

## Usage (without VS Code)

Agent Sandbox is editor-agnostic. You can run the runtime stack directly:

```bash
cd runtime/compose
docker compose up -d
docker compose logs -f proxy
```

Then exec into the agent container:

```bash
docker compose exec agent zsh
```

## Policies

Policies live under `runtime/policy/` and are intended to be:

- reviewed like code
- shared across projects
- easy to tighten over time

Common policy concepts:

- allowedDomains: outbound allowlist for the proxy
- profiles like strict vs dev
- project overrides via .devcontainer/policy-overrides.yaml (optional)

## Images

### Base image

agent-sandbox-base includes:

- core shell tooling (bash, coreutils)
- git + common dev utilities (jq, rg, fd, curl, ca-certs)
- tmux (recommended for long-running agent sessions)
- hardening defaults (non-root user, safe paths)

### Agent images

Agent images extend the base with only what is needed for that agent:

- agent-claude
- agent-codex
- more to come?

## Reproducibility and updates

Recommended workflow for teams:

- build and publish images in CI
- pin images by digest in devcontainer configs
- update agent versions by bumping a digest and opening a PR

This avoids "same Dockerfile, different image" drift.

## Security notes (local)

This project is designed to reduce risk, not eliminate it.

Key principles:

- minimize mounts: only the repo workspace + project-scoped state
- prefer short-lived credentials (SSO/STS) and read-only IAM roles
- route all outbound through the proxy and review logs
- run long-lived agent sessions in tmux so VS Code reconnects do not kill the process

If you discover a sandbox escape or bypass, please open a security issue (see below).

## Roadmap

- [ ] CLI (agentbox) for init, up, logs, bump
- [ ] More agent images and adapters
- [ ] Stronger "no direct egress" enforcement (VM-level rules)

## Contributing

PRs welcome:

- new agent images
- improved proxy policy/lists
- templates for common stacks
- docs and examples

Please keep changes:

- agent-agnostic where possible
- policy-as-code friendly
- compatible with Colima on macOS

## Security

If you believe you have found a security issue or bypass, please:

- open a GitHub Security Advisory (preferred), or
- open an issue with minimal reproduction details

## License

[MIT License](./LICENSE)
