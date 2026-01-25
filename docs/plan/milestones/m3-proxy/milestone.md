# m3-proxy

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

### m3.2-firewall-lockdown

Update iptables to force all traffic through proxy.

- Remove domain-based ipset rules
- Remove SSH allowance (port 22)
- Allow only: localhost, Docker DNS, Docker host network (for proxy)
- Drop everything else
- Update verification to test proxy connectivity instead of direct domain access

### m3.3-proxy-enforcement

Add allowlist enforcement to the proxy.

- mitmproxy addon that checks CONNECT requests against allowlist
- Read allowlist from mounted policy.yaml
- Block non-allowed requests with clear error message
- Environment variable to toggle discovery/enforcement mode
- Support same policy format as before (services + domains)

### m3.4-git-https

Configure git to use HTTPS instead of SSH.

- Add git config to image that rewrites SSH URLs to HTTPS
- Document credential caching options (credential helper, gh auth)
- Test clone/push/pull work through proxy
- Update any documentation that references SSH

### m3.5-devcontainer-integration

Make devcontainer use the compose-based proxy setup.

- Create docker-compose.yml in .devcontainer/ (or reference root compose file)
- Update devcontainer.json to use `dockerComposeFile` instead of `build`
- Configure VS Code to attach to agent service
- Test full workflow in VS Code

### m3.6-cleanup

Retire iptables-only approach and update documentation.

- Remove domain resolution logic from init-firewall.sh
- Remove ipset creation (no longer needed)
- Update CLAUDE.md with new architecture
- Update README with proxy-based setup
- Document discovery workflow for new agents

## Open Questions

1. **Log rotation**: Proxy logs will grow. Defer until it becomes a problem, then add logrotate or size limits.

2. **Policy file location for proxy**: Mount from host or bake into image? Probably mount for flexibility, same pattern as iptables policy.

3. **Devcontainer rebuild experience**: When proxy policy changes, does user need to rebuild? Ideally just restart.

## Definition of Done

- [ ] iptables blocks all direct outbound (only proxy allowed)
- [ ] Proxy enforces domain allowlist
- [ ] Git works over HTTPS through proxy
- [ ] Devcontainer works with proxy sidecar
- [ ] Documentation updated
- [ ] Old iptables-only code removed
