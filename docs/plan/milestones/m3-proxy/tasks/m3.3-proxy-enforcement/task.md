# Task: m3.3 - Proxy Enforcement

## Summary

Add domain allowlist enforcement to the mitmproxy addon. The proxy currently logs all traffic in discovery mode. This task adds the ability to block requests to non-allowed domains based on the same policy.yaml format used elsewhere.

## Scope

- Extend the mitmproxy addon to enforce a domain allowlist
- Read allowlist from mounted policy.yaml
- Toggle between log and enforcement mode via environment variable
- Block disallowed CONNECT requests with a clear error
- Ship a default policy.yaml baked into the proxy image (github only)
- Do NOT change the firewall or base image

## Acceptance Criteria

- [x] PROXY_MODE=enforce blocks CONNECT requests to non-allowed domains
- [x] PROXY_MODE=log allows everything, logs only (same as today's behavior)
- [x] Proxy refuses to start in enforce mode without a policy file
- [x] Blocked requests return HTTP 403 with a message identifying the blocked domain
- [x] Allowed domains loaded from /etc/mitmproxy/policy.yaml (mounted into proxy container)
- [x] Default policy.yaml baked into proxy image allows github only
- [x] The `services: [github]` entry resolves to github.com and *.github.com (not IP ranges, since the proxy sees hostnames)
- [x] Plain HTTP requests to non-allowed domains are also blocked
- [x] JSON log entries include an "action" field: "allowed" or "blocked"

## Applicable Learnings

- mitmproxy can read SNI from TLS ClientHello without MITM decryption, enabling hostname logging for HTTPS
- HTTP_PROXY/HTTPS_PROXY env vars are opt-in; applications can ignore them and connect directly (iptables handles this)
- Policy files that control security must live outside the workspace and be mounted read-only
- "Baked default + optional override" pattern works well for security-sensitive config
- The `services` key in policy.yaml currently maps to IP range fetching; for the proxy, it should map to domain patterns instead

## Plan

### Files Involved

- `images/proxy/addons/logger.py` - Extend with enforcement logic (major changes)
- `images/proxy/Dockerfile` - Add PyYAML dependency for policy parsing
- `docker-compose.yml` - Mount policy.yaml into proxy container, add PROXY_MODE env var

### Approach

The current `logger.py` addon has three hooks: `http_connect`, `response`, and `error`. Enforcement plugs into two of these:

1. `http_connect` - This is where HTTPS CONNECT tunnels are established. If the target host is not on the allowlist, kill the flow with a 403 before the tunnel is created.
2. `request` - Replace `response` hook for plain HTTP. Check the host before forwarding. Block with 403 if not allowed.

Policy loading:
- Read `/etc/mitmproxy/policy.yaml` at addon startup
- Parse `domains` list as exact-match hostnames
- Parse `services` list and expand to domain patterns:
  - `github` maps to `github.com`, `*.github.com`, `githubusercontent.com`, `*.githubusercontent.com`
- If PROXY_MODE is "log", skip enforcement
- If PROXY_MODE is "enforce" and no policy file exists, refuse to start (exit with error)

Domain matching:
- Exact match for entries without wildcards
- Suffix match for wildcard entries (e.g., `*.github.com` matches `api.github.com`)
- Port is not checked (any port to an allowed domain is allowed)

Logging changes:
- Add `"action": "allowed"` or `"action": "blocked"` to all log entries
- In log mode, action is always "allowed"

### Service-to-Domain Mapping

The `services` key in policy.yaml needs a different interpretation in the proxy context. The iptables approach fetched IP ranges. The proxy sees hostnames, so we map service names to domain patterns:

```
github:
  - github.com
  - *.github.com
  - githubusercontent.com
  - *.githubusercontent.com
```

This is a static mapping baked into the addon code. If we need more services later, we add them to the map.

### Implementation Steps

1. Add PyYAML to proxy Dockerfile
2. Create default policy.yaml for proxy image (github only)
3. COPY default policy.yaml into proxy image at /etc/mitmproxy/policy.yaml
4. Extend logger.py with policy loading and domain matching
5. Add enforcement to http_connect and request hooks
6. Add PROXY_MODE env var to docker-compose.yml
7. Mount agent policy.yaml into proxy container (overrides baked-in default)
8. Test: enforce mode blocks disallowed domain
9. Test: enforce mode allows allowed domain
10. Test: log mode allows everything
11. Test: enforce mode without policy file refuses to start

### Open Questions

1. Should we support wildcard entries in the `domains` list (e.g., `*.anthropic.com`)? Leaning yes, since it's simple to implement and useful.
2. Should the github service mapping include `objects.githubusercontent.com` and other CDN subdomains? They're covered by `*.githubusercontent.com`.
3. Should we add a `--set` option to mitmproxy instead of an env var for mode selection? Env var is simpler and consistent with HTTP_PROXY pattern.
