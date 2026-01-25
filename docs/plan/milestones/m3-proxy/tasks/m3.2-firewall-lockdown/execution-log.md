# Execution Log: m3.2 - Firewall Lockdown

## Implementation complete

Rewrote `images/base/init-firewall.sh` and updated `images/base/entrypoint.sh`.

### Changes made

**init-firewall.sh**: Reduced from 175 lines to 93. Removed:
- All ipset usage (create, add, match-set)
- Policy file reading (POLICY_FILE, yq parsing)
- GitHub API calls for IP ranges
- Domain DNS resolution (dig)
- SSH port 22 allowance
- Broad DNS allowance (UDP 53 to anywhere)

Kept:
- Docker DNS NAT rule preservation
- Flush and rebuild pattern
- Loopback allowance
- Host network detection and allowance
- Default DROP policies
- REJECT with ICMP for immediate feedback
- Verification tests (adapted)

**entrypoint.sh**: Changed idempotency check from `ipset list allowed-domains` to `iptables -S OUTPUT | grep "^-P OUTPUT DROP"`.

### Verification approach

The negative test uses `curl -x "" https://example.com` with `-x ""` to explicitly bypass the HTTP_PROXY env var. This ensures we're testing direct outbound, not proxy-routed traffic.

The positive test pings the host network gateway. This is a WARN (not ERROR) if it fails, because some Docker runtimes don't respond to ICMP from containers.

### Known impact

**Devcontainer is broken by this change.** The devcontainer runs a single container without a proxy sidecar. The new firewall locks down to host network only, meaning zero external network access. This is expected and will be addressed in m3.5-devcontainer-integration. The devcontainer needs to migrate to a compose backend to support the proxy sidecar.

### Testing

Requires image rebuild from host:
```bash
./images/build.sh
docker compose down && docker compose up -d
docker compose exec agent zsh
# Verify: curl https://example.com should fail
# Verify: curl -x http://proxy:8080 https://api.github.com/zen should work
```
