# m3-proxy

Add proxy-based network observability and enforcement as a complement to iptables.

## Motivation

The iptables approach works for enforcement but provides no visibility into what requests agents actually make. Before building out multi-agent support (m4), we need to understand what endpoints each agent needs. A proxy gives us:

- Request-level logging (hostname, method, status)
- Discovery mode to observe traffic before defining policy
- Foundation for future enforcement at the request level

## Goals

- Run mitmproxy as a sidecar container
- Route agent traffic through the proxy via environment variables
- Structured JSON logging of all requests
- Discovery mode first (log everything, block nothing)
- Later: enforcement mode with allowlist

## Non-goals (for now)

- MITM inspection of request/response bodies (CONNECT passthrough is sufficient)
- CA certificate injection
- Path-level or method-level filtering
- Replacing iptables (proxy is complementary)

## Design Decisions

### Proxy choice: mitmproxy

Considered alternatives:
- **Squid**: Battle-tested but config is arcane, logging less structured
- **Nginx**: Better as reverse proxy, forward proxy support is awkward
- **Custom Go proxy**: Full control but significant effort

mitmproxy wins because:
- Designed for traffic inspection and logging
- Excellent structured JSON output via `--set hardump=...` or event hooks
- Python scripting for custom logging/filtering
- Good docs, active community
- Easy to run in transparent or explicit proxy mode

### Proxy mode: explicit (not transparent)

Two ways to route traffic through a proxy:

1. **Transparent proxy**: iptables redirects traffic to proxy. App doesn't know.
2. **Explicit proxy**: App configured via `HTTP_PROXY`/`HTTPS_PROXY` env vars.

Explicit is simpler:
- No iptables complexity in the proxy path
- Works with standard tooling (curl, npm, pip all respect proxy env vars)
- Claude Code and other agents should respect these vars
- Easier to debug (can disable by unsetting env var)

### HTTPS handling: CONNECT passthrough

For HTTPS, the proxy sees a CONNECT request to `host:443`, then tunnels encrypted traffic.

What we can log without MITM:
- Destination hostname and port
- Timestamp
- Connection duration
- Bytes transferred

What we cannot log without MITM:
- Full URL path
- Request/response headers
- Request/response bodies

Hostname-level logging is sufficient for building domain allowlists. If we need path-level visibility later, we can add MITM with CA injection as a separate task.

### Logging format

mitmproxy can output structured logs via addon scripts. Target format:

```json
{"timestamp": "2024-01-15T10:30:00Z", "client": "172.18.0.2", "method": "CONNECT", "host": "api.anthropic.com", "port": 443, "status": 200}
{"timestamp": "2024-01-15T10:30:01Z", "client": "172.18.0.2", "method": "GET", "host": "api.github.com", "port": 443, "path": "/meta", "status": 200}
```

For HTTPS CONNECT tunnels, we log the CONNECT. For plain HTTP, we log the full request.

### Container architecture

```
┌─────────────────────────────────────────────────┐
│ Docker Compose Stack                            │
│                                                 │
│  ┌─────────────┐      ┌─────────────┐          │
│  │   agent     │─────▶│   proxy     │─────▶ internet
│  │             │      │ (mitmproxy) │          │
│  │ HTTP_PROXY= │      │             │          │
│  │ proxy:8080  │      │ :8080       │          │
│  └─────────────┘      └─────────────┘          │
│                              │                  │
│                              ▼                  │
│                       /var/log/proxy/           │
│                       (volume mount)            │
└─────────────────────────────────────────────────┘
```

The proxy container:
- Runs mitmproxy in regular (non-transparent) mode on port 8080
- Writes structured logs to a mounted volume
- In discovery mode: allows all traffic
- In enforcement mode: applies allowlist

The agent container:
- Sets `HTTP_PROXY` and `HTTPS_PROXY` to `http://proxy:8080`
- All HTTP/HTTPS traffic routes through proxy
- iptables firewall still runs (defense in depth) but allows proxy container

## Tasks

### m3.1-proxy-container

Create the mitmproxy container image and compose service.

- Dockerfile based on `mitmproxy/mitmproxy` official image
- Custom addon script for structured JSON logging
- Compose service definition with volume for logs
- Health check

### m3.2-agent-integration

Configure agent container to route through proxy.

- Add proxy env vars to compose service
- Verify curl/npm/pip respect proxy
- Verify Claude Code respects proxy
- Update iptables rules to allow traffic to proxy container

### m3.3-log-analysis

Tools to analyze proxy logs and extract domain lists.

- Script to parse JSON logs and output unique domains
- Script to generate policy.yaml from observed traffic
- Documentation for discovery workflow

### m3.4-enforcement-mode

Add allowlist enforcement to the proxy.

- mitmproxy addon that checks requests against allowlist
- Read allowlist from policy.yaml (same format as iptables)
- Block non-allowed requests with clear error
- Toggle between discovery and enforcement mode

## Open Questions

1. Should proxy replace iptables or complement it? Current thinking: complement (defense in depth).
2. How to handle non-HTTP traffic (git over SSH)? Current thinking: SSH continues to bypass proxy, handled by iptables only.
3. Log rotation strategy? Defer until logs become unwieldy.

## Definition of Done

- [ ] Proxy container runs alongside agent container
- [ ] All HTTP/HTTPS traffic from agent routes through proxy
- [ ] Requests logged in structured JSON format
- [ ] Can extract unique domains from logs
- [ ] Documentation for discovery workflow
- [ ] (stretch) Enforcement mode with allowlist
