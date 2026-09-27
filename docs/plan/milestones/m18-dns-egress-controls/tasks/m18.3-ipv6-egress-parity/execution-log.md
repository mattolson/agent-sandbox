# Execution Log: m18.3 - ipv6 egress parity

## 2026-09-27 - IPv6 enabled on the dev network: self-tests pass, clients fall back

The maintainer added `networks: default: enable_ipv6: true` to `user.override.yml` and recreated the stack. Docker
29.2.1 assigned `fd9f:73ac:d109::/64` with no `ipam` block; `eth0` has `fd9f:73ac:d109::3` and a default route via
`fd9f:73ac:d109::1`. The container started, and a re-run of the firewall printed
`IPv6: present on eth0 (fd9f:73ac:d109::3/64)` and passed every self-test, including both IPv6 rejects and `::1`.

**Observation:** `getent hosts proxy` now returns `fd9f:73ac:d109::2` alone, so the `ahostsv4` fix was necessary:
without it the firewall would have refused to start on this network. `resolv.conf` still names `172.22.0.2`.

**Observation:** A TCP connect over IPv6 to a public resolver, and to the proxy's own IPv6 address, fails with
`Permission denied` (EACCES). That settles open question 6; `errno_result` already maps it. curl through the proxy
tries `[fd9f:73ac:d109::2]:8080` first, is refused at once, and connects to `172.22.0.2` in the same attempt;
`gh api`, `git ls-remote`, and a Go module listing all completed in under 0.7 s. The AAAA answer from the sinkhole
costs one immediate refusal, as planned.

## 2026-09-27 - IPv4 unchanged: after-m18.2 audit clean on the new base image

`run-audit.bash --stage after-m18.2` in CLI mode matched every compared row (`results/after-m18.2-20260927-154352/`,
a working file). The A, B, C, and S rows read exactly as on 2026-09-15, and H5 shows the same 15 IPv4 rules. That
is the third acceptance criterion. The IPv6 dump in H5 is the planned rule set and nothing else: DROP policies on
all three chains, `::1` accepted on `lo` in each direction, established and related in each direction, and the
final `REJECT --reject-with icmp6-adm-prohibited`. E1 through E4 still read `absent` and `unreachable`, because
the network has `EnableIPv6=false`.

**Observation:** H1's capture was live but saw no port 53 traffic at all: `tcpdump` listened on `any` for the full
window and exited on the timeout, with 0 packets captured, against 56 on 2026-09-15. So `not-seen` holds, but this
run has no positive control showing the capture would have seen a query. The earlier traffic most likely came from
the H3 throwaway container's lookup landing inside the window. For the after-m18.3 run, check that
`vm-capture.txt` is non-empty or send a query from the VM during the window, so H1 is evidence rather than silence.

## 2026-09-27 - IPv6-absent path verified in the rebuilt dev image

The maintainer ran `make setup`. The installed `/usr/local/bin/init-firewall.sh` matches the branch, and the
container started, so the boot-time run passed. A re-run in place with `sudo` printed
`IPv6: absent on eth0 (disable_ipv6=1); ip6tables default-deny installed anyway`, then every self-test passed: the
sinkhole resolves `proxy` and refuses a random `.invalid` name with `NXDOMAIN`, direct outbound to `1.1.1.1` is
blocked, the IPv6-absent line, and `::1` open. `getent ahostsv4 proxy` returns `172.22.0.2`. This covers the second
acceptance criterion's start path. The IPv4 audit (`--stage after-m18.2`) and the IPv6-enabled run are still to do
on the host; the override is not in `user.override.yml` yet.

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
