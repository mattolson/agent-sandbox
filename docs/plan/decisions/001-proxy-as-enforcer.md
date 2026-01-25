# 001: Proxy as Enforcer, iptables as Gatekeeper

## Status

Accepted

## Context

The original architecture used iptables with ipset for network enforcement:

1. At container startup, resolve allowed domains to IP addresses
2. Add IPs to an ipset
3. iptables allows traffic to IPs in the ipset, drops everything else

This worked but had limitations:

- No visibility into actual requests (only IP-level blocking)
- IP addresses can change after resolution (stale allowlist)
- No logging of what endpoints agents attempt to reach
- Complex ipset management for services like GitHub with many IP ranges

We added a mitmproxy sidecar (m3.1) for observability, routing traffic via `HTTP_PROXY` environment variables. This provided logging but introduced a security gap: agents could bypass the proxy by ignoring the env vars and connecting directly.

The question became: how do these two mechanisms work together?

## Decision

Invert the enforcement model:

- **iptables** becomes a gatekeeper that blocks all outbound traffic except to the proxy container
- **Proxy** becomes the enforcer that checks requests against the domain allowlist

The agent cannot bypass either layer:
- Ignoring `HTTP_PROXY` fails because iptables blocks direct connections
- The proxy is in a separate container the agent cannot modify

Additionally, block SSH entirely and require git to use HTTPS. SSH to arbitrary hosts is a data exfiltration vector that bypasses the proxy.

## Rationale

**Why not keep iptables as enforcer with proxy as optional observer?**

- Agents can bypass `HTTP_PROXY` env vars trivially
- Running both enforcement mechanisms is complex and redundant
- Domain-based proxy enforcement is more intuitive than IP-based iptables rules

**Why not transparent proxy (iptables REDIRECT)?**

- Works well when proxy is local (same container)
- Cross-container transparent proxy requires TPROXY or complex routing
- Explicit proxy with iptables gatekeeper achieves the same security with simpler networking

**Why not run proxy inside agent container?**

- Agent could kill/modify the proxy process
- Agent could modify iptables rules (has NET_ADMIN for setup)
- Sidecar model provides process isolation

**Why block SSH?**

- SSH to arbitrary hosts bypasses the HTTP proxy entirely
- Could be used for data exfiltration or tunneling
- Git works fine over HTTPS
- Simpler to block entirely than to allowlist specific SSH endpoints

## Consequences

**Positive:**
- Single enforcement point (proxy) with domain-level granularity
- Full request logging for observability and debugging
- Simpler mental model for users
- No stale IP resolution issues

**Negative:**
- Git must use HTTPS (minor inconvenience, well-documented workaround)
- Non-HTTP protocols are blocked entirely (acceptable for coding agent use case)
- Proxy becomes a critical path component (must be healthy for agent to work)

**Migration:**
- init-firewall.sh changes significantly (removes domain resolution, ipset)
- Policy file format stays the same (services + domains)
- Policy enforcement moves from iptables script to mitmproxy addon
- Devcontainer must use compose backend for sidecar support
