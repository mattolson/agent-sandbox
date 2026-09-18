# Execution Log: m18.3 - ipv6 egress parity

## 2026-09-17 - Planning

Context gathered from this sandbox, which runs on the rebuilt `m18.2` stack: `disable_ipv6` is 1 on `eth0` and 0
on `all`, `lo` has `::1`, `ip -6 route` is empty, and the latest audit's `ip6tables -S` shows ACCEPT policies with
no rules. The compose templates define no `networks:` section, so the stack uses compose's default network with
Docker's default of no IPv6. mitmproxy binds the DNS mode dual-stack when `listen_host` is empty
(`mode_servers.py`: a TCP server through asyncio plus UDP servers on `0.0.0.0` and `::`), so the sinkhole needs no
change. `probe.bash`'s `errno_result` maps `EPERM` and `EHOSTUNREACH` to `rejected` but not `EACCES`, which is the
errno expected for an ICMPv6 administratively-prohibited reject on a TCP connect.

**Decision (proposed):** deny all IPv6 except loopback and established traffic, instead of mirroring the IPv4
exceptions for the host network and port 53. The agent reaches the proxy over IPv4 by construction, so the mirrored
exceptions would be paths with no consumer. Rationale and the two alternatives in `task.md`. Awaiting approval.

**Issue:** Docker's documentation is outside the sandbox allowlist, so whether `enable_ipv6: true` on a compose
network gets a unique-local prefix automatically, and what Docker does for DNS over IPv6, are open questions for
the host.
