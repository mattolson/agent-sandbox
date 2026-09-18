# Execution Log: m18.3 - ipv6 egress parity

## 2026-09-17 - Approved and implemented from the sandbox

The maintainer approved deny-all IPv6, keeping IPv6 enabled in this repo's dev sandbox, and leaving the sinkhole's
AAAA answers alone. Docker Engine on Colima is 29.2.1, so `enable_ipv6: true` without a subnet gets a unique-local
prefix from the daemon and the override needs no `ipam` block.

**Decision:** Loopback over IPv6 is `::1` only (`-o lo -d ::1`, `-i lo -d ::1`), instead of the planned
learn-before-flush step for IPv6 resolver addresses. The learn step could only see Docker's original `resolv.conf`
on a first start, and the address of an IPv6 stub, if Docker ever installs one, is unknown here. A loopback rule
that admits nothing but `::1` denies such a listener without knowing it, on a re-run too. The cost is local
delivery to the container's own global IPv6 address, which nothing in the sandbox uses.

**Issue:** `getent hosts proxy` prefers the AAAA record. On a network with IPv6 the firewall's `resolve_proxy`
would print nothing, because its awk filter keeps only dotted quads, and the container would refuse to start; the
audit's `PROXY_ADDR` would become the IPv6 address and the S rows would read `rejected`. Both now use
`getent ahostsv4`, which asks for A records only. Found by reading, not by running: IPv6 is off in this sandbox
until the override lands and the stack is recreated.

**Issue:** `.agent-sandbox/` is mounted read-only inside the sandbox, so the override that enables IPv6 cannot be
written from here. It is a host-side step in the implementation checklist, with the snippet in the audit README.

**Issue:** None of the firewall change can run here. `sudo` allows only the installed script and `ip6tables` needs
`NET_ADMIN`; `bash -n` is the only check available. The maintainer's run is the test.

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
