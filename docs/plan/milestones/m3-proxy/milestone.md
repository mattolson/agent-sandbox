# m3-proxy

**Status: Complete**

Proxy-based network enforcement and observability, replacing domain-based iptables rules.

## Motivation

The original iptables approach resolves domains to IPs at container startup and blocks everything else. This works but has limitations:

- No visibility into what requests agents actually make
- IP addresses can change after resolution
- No request-level logging for debugging or discovery
- Complex ipset management

A proxy-based approach provides:

- Request-level logging with hostnames (not just IPs)
- Domain-based enforcement that works with dynamic IPs
- Discovery mode to observe traffic before defining policy
- Simpler mental model (one enforcement point)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Docker Compose Stack                                        │
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────┐      │
│  │   agent container   │      │   proxy container   │      │
│  │                     │      │   (mitmproxy)       │      │
│  │  ┌───────────────┐  │      │                     │      │
│  │  │ iptables      │  │      │  - Logs all traffic │      │
│  │  │               │  │      │  - Enforces policy  │      │
│  │  │ ALLOW proxy   │──┼─────▶│  - Can't be bypassed│─────▶│ internet
│  │  │ ALLOW Docker  │  │      │                     │      │
│  │  │ DROP all else │  │      └─────────────────────┘      │
│  │  └───────────────┘  │                                    │
│  │                     │                                    │
│  │  HTTP_PROXY=proxy   │                                    │
│  └─────────────────────┘                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: iptables forces all traffic through the proxy. The agent can ignore `HTTP_PROXY` env vars, but direct connections are blocked. The proxy becomes the single enforcement point.

## Design Decisions

### Proxy choice: mitmproxy

- Designed for traffic inspection and logging
- Python scripting for custom enforcement logic
- Structured JSON output via addons
- Active community, good docs

### iptables as gatekeeper, proxy as enforcer

- iptables: blocks all outbound except to proxy container and Docker internals
- Proxy: logs all requests, enforces domain allowlist
- Agent cannot bypass either layer

### No SSH (git over HTTPS only)

SSH to arbitrary hosts is a data exfiltration vector. By blocking SSH entirely:

- Git must use HTTPS (works fine, just needs credential setup)
- No covert channels via SSH tunneling
- Simpler security model

Users configure git with:
```bash
git config --global url."https://github.com/".insteadOf git@github.com:
```

### Discovery vs enforcement modes

The proxy supports two modes:

- **Discovery mode**: Log all requests, allow everything. Use to observe what endpoints an agent needs.
- **Enforcement mode**: Log all requests, block those not on allowlist. Use in production.

Mode is controlled by environment variable on the proxy container.

### Host network access

The Docker host network (e.g., 172.18.0.0/24) is allowed. This enables:

- Communication with proxy container
- Communication with other sidecar services
- Docker DNS resolution

This is acceptable because other containers in the compose stack are explicitly configured and trusted.

## Tasks

### m3.1-proxy-container (DONE)

Create the mitmproxy container image and compose service.

- [x] Dockerfile based on `mitmproxy/mitmproxy` official image
- [x] Custom addon script for structured JSON logging
- [x] Compose service definition with health check
- [x] Agent container routes through proxy via env vars

### m3.2-firewall-lockdown (DONE)

Update iptables to force all traffic through proxy.

- [x] Remove domain-based ipset rules
- [x] Remove SSH allowance (port 22)
- [x] Allow only: localhost, Docker DNS, Docker host network (for proxy)
- [x] Drop everything else
- [x] Update verification to test proxy connectivity instead of direct domain access

### m3.3-proxy-enforcement (DONE)

Add allowlist enforcement to the proxy.

- [x] mitmproxy addon that checks CONNECT requests against allowlist
- [x] Read allowlist from mounted policy.yaml
- [x] Block non-allowed requests with clear error message
- [x] Environment variable to toggle discovery/enforcement mode
- [x] Support same policy format as before (services + domains)

### m3.4-devcontainer-ux (DONE)

Validate and refine the devcontainer experience. Use this repo as the test case before finalizing the template.

**Problem**: The current template has a single docker-compose.yml at project root shared by both VS Code devcontainer and CLI usage. This causes:

1. Container/volume name conflicts if both run simultaneously
2. Policy conflicts: VS Code needs Microsoft/extension domains that CLI doesn't

**Solution**: Separate compose files with isolated naming and different policies.

**Structure:**

```
.devcontainer/
  devcontainer.json           # Points to ./docker-compose.yml
  docker-compose.yml          # VS Code mode: relaxed policy, namespaced resources
docker-compose.yml            # CLI mode: tight policy, standard naming
docs/policy/examples/
  claude.yaml                 # Base Claude Code policy (CLI)
  claude-devcontainer.yaml    # Adds VS Code domains (devcontainer)
```

**Subtasks:**

Proxy changes:
- [x] Add `vscode` service to SERVICE_DOMAINS in enforcer.py (update.code.visualstudio.com, marketplace.visualstudio.com, *.vsassets.io, etc.)

Policy examples:
- [x] Create `docs/policy/examples/claude-devcontainer.yaml` with `services: [github, vscode]`
- [x] Verify `docs/policy/examples/claude.yaml` works for CLI usage

This repo's devcontainer:
- [x] Create `.devcontainer/docker-compose.yml` with namespaced container/volume names
- [x] Update `.devcontainer/devcontainer.json` to use `dockerComposeFile` backend
- [x] Remove `.devcontainer/Dockerfile` (no longer needed, use published image)
- [x] Remove `.devcontainer/policy.yaml` (policy now in proxy image or host mount)
- [x] Test full VS Code workflow: open in container, proxy works, firewall blocks direct

Template updates:
- [x] Update `templates/claude/.devcontainer/` to match validated structure
- [x] Update `templates/claude/docker-compose.yml` for CLI-only usage
- [x] Update `templates/claude/README.md` with clear separation of modes

Cleanup (rolled into this task):
- [x] Update root CLAUDE.md with new architecture
- [x] Update root README.md with proxy-based setup
- [x] Remove any remaining iptables-only code paths

### m3.5-git-https (DONE)

Configure git to use HTTPS instead of SSH.

Port 22 is blocked by the firewall (prevents tunneling that could bypass the proxy). This task ensures git operations work via HTTPS.

- [x] Add `git config --global url."https://github.com/".insteadOf git@github.com:` to base image
- [x] Add `git config --global url."https://github.com/".insteadOf ssh://git@github.com/` to base image
- [x] Document HTTPS-only constraint in README (explain why SSH is blocked)
- [x] Document credential options: `gh auth login`, fine-grained PAT, host-based git
- [x] Test clone/push/pull work through proxy

## Open Questions

1. **Log rotation**: Proxy logs will grow. Defer until it becomes a problem, then add logrotate or size limits.

2. ~~**Policy file location for proxy**: Mount from host or bake into image?~~ Resolved: Bake default into image, allow host mount override.

3. ~~**Devcontainer rebuild experience**: When proxy policy changes, does user need to rebuild?~~ Resolved: Just restart proxy container.

4. **VS Code domain coverage**: Need to discover all domains VS Code needs. May require running in discovery mode and observing traffic.

## Definition of Done

- [x] iptables blocks all direct outbound (only proxy allowed)
- [x] Proxy enforces domain allowlist
- [x] Git works over HTTPS through proxy
- [x] Devcontainer works with proxy sidecar (separate compose file, isolated from CLI mode)
- [x] CLI and devcontainer can run simultaneously without conflicts
- [x] Template refined and validated on this repo
- [x] Documentation updated
- [x] Old iptables-only code paths removed
