# Task: m3.2 - Firewall Lockdown

## Summary

Rewrite init-firewall.sh to force all traffic through the proxy sidecar. Remove domain-based ipset rules, SSH allowance, and external DNS. The firewall becomes a simple gatekeeper.

## Scope

- Rewrite init-firewall.sh to proxy-gatekeeper mode
- Update entrypoint.sh idempotency check (ipset no longer exists)
- Update verification tests
- Do NOT remove packages from Dockerfile (defer to m3.6-cleanup)
- Do NOT modify proxy container or addons

## Acceptance Criteria

- [ ] iptables blocks all direct outbound connections (curl to any external host fails)
- [ ] Localhost traffic works (Docker DNS at 127.0.0.11, loopback)
- [ ] Host network traffic works (proxy container reachable)
- [ ] SSH (port 22) is blocked
- [ ] No ipset usage
- [ ] No policy file parsing in firewall script
- [ ] Entrypoint idempotency check works without ipset
- [ ] Container starts successfully with proxy sidecar

## Applicable Learnings

- iptables rules must preserve Docker's internal DNS resolution (127.0.0.11 NAT rules) or container DNS breaks
- Docker internal DNS at 127.0.0.11 is on loopback, covered by localhost rules
- Docker DNS forwarding to host resolver happens outside the container's network namespace, so container iptables never sees it
- Entrypoint scripts should be idempotent
- Debian's `env_reset` in sudoers prevents POLICY_FILE override via environment

## Plan

### Files Involved

- `images/base/init-firewall.sh` - Rewrite (major changes)
- `images/base/entrypoint.sh` - Update idempotency check

### Approach

The current init-firewall.sh does too much: DNS resolution, GitHub API calls, ipset management, domain-to-IP translation. All of that moves to the proxy. The new script is a simple lockdown:

1. Preserve Docker DNS NAT rules (same as before)
2. Flush all existing rules (same as before)
3. Restore Docker DNS NAT rules (same as before)
4. Allow localhost (covers Docker DNS at 127.0.0.11)
5. Allow host network (covers proxy and other compose services)
6. Set default DROP
7. Allow established/related connections
8. Reject everything else with ICMP for immediate feedback
9. Verify lockdown works

What gets removed:
- DNS to anywhere (UDP 53 to any) - Docker DNS is on loopback, already allowed
- SSH (port 22) - blocked per decision 002
- ipset creation and population
- Policy file reading (services, domains)
- GitHub IP range fetching
- Domain DNS resolution

Verification changes:
- Negative test: direct curl to example.com fails (same)
- Positive test: verify host network gateway is reachable (replaces "verify allowed domain")

Entrypoint changes:
- Replace `ipset list allowed-domains` check with `iptables -S OUTPUT | grep "^-P OUTPUT DROP"` to detect if firewall is already initialized

### Implementation Steps

- [ ] Rewrite init-firewall.sh
- [ ] Update entrypoint.sh idempotency check
- [ ] Test: container starts with proxy sidecar
- [ ] Test: direct curl to external host fails
- [ ] Test: traffic through proxy works (curl via HTTP_PROXY)

### Open Questions

1. Should the firewall script still read the policy file at all? No - the proxy handles policy now. The script has no configuration.
2. Should we verify proxy reachability in the firewall script? The proxy is on the host network, which is allowed. Compose healthcheck already ensures proxy is up. A simple gateway ping is sufficient for positive verification.
