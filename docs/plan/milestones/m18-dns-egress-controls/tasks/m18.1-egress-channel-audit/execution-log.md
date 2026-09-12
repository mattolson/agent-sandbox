# Execution Log: m18.1 - egress channel audit

## 2026-09-12 - Probe script, runner, expectations, and matrix written; in-container baseline measured

Planning was approved with two answers: no domain to delegate, so tcpdump is the demonstration, and the maintainer
will run host-side steps from scripts. The unanswered questions went with the plan's recommendations.

**Issue:** The first `probe.bash` opened the UDP socket inside `$( ... )` to capture the error text, so the
descriptor lived in the subshell and every send got `Bad file descriptor`.
**Solution:** Open the socket in the main shell with the group's stderr sent to a temp file, then read the file.

**Issue:** The DoH probe reported `curl-56`. A proxy 403 to a `CONNECT` request never produces a response body,
and curl reports it as a receive failure.
**Solution:** Read `%{http_connect}` from curl's write-out and treat a 403 there as `proxy-403`.

**Decision:** The peer on the compose network is a small python DNS responder in `python:3-alpine`, not busybox
`nc`. A real reply makes B3 and B4 conclusive from inside the container, it handles both transports and many
connections, and it doubles as the `dns:` target for H3, where a forwarded lookup answering `203.0.113.1` shows the
embedded resolver forwarded to it.

**Decision:** D3 and D4 use `proxy` and `localhost` as temporarily allowed names rather than a public wildcard DNS
service. The renderer accepts dot-less hosts, nothing outside the sandbox is involved, and the two names cover the
bridge-network and loopback classes the `m18.4` guard must refuse.

**Observation:** In-container baseline from this sandbox, label `a1b2c3d4`:

- A1 answered, A2 not-found, A3 answered (2 answers), A4 answered (98 bytes), A5 noerror-empty, A6 nxdomain
  (271 bytes), A7 answered, A8 answered
- B1 timeout, B2 conn-refused
- C1 through C5 rejected
- D1 proxy-403
- E1 absent, E2 through E4 unreachable, E5 timeout

**Observation:** Docker's `resolv.conf` comment marks the upstream as `host(192.168.5.1)`. The container cannot
reach that address (C1, C2), yet resolution works (A1), so the embedded resolver dials the upstream from outside the
container's namespace. The current firewall never sees the forward. Recorded as finding 2 in the matrix doc; H3
checks what `dns:` changes.

**Issue:** Partway through, `/workspace` was switched to another branch by a separate checkout. The branch and its
commits were untouched and the new files were untracked, so they survived.
**Solution:** Gave the branch its own worktree under `.claude/worktrees/` and finished there rather than switching
`/workspace` back under whoever is using it.

**Learning:** Capturing stderr from `exec` redirections needs `{ exec 3<>...; } 2>file`. Putting `2>/dev/null`
directly on the `exec` silences the shell for the rest of the script, and wrapping it in `$( ... )` loses the
descriptor.

## 2026-09-12 - Planning spike from inside the dev sandbox

Checked what the audit can rely on and probed the resolver paths from this container before settling the design.

**Observation:** `/etc/resolv.conf` points at `127.0.0.11` with `ndots:0`, and Docker's comment block names the
upstream as `host(192.168.5.1)`, the Lima gateway. `eth0` has `172.22.0.3/16` and no IPv6 address or route. The
images have `curl`, `openssl`, `getent`, `ip`, and `ss`, and none of `dig`, `nslookup`, `host`, `nc`, `tcpdump`, or
a system `python3`. `sudo -l` confirms the `dev` user can run only the three init scripts, so iptables state is not
readable from inside.

**Decision:** Probes are pure bash. Query packets are built with `printf` and sent through `/dev/udp` and `/dev/tcp`.
This runs unchanged in every agent image and needs nothing installed.

**Issue:** The first attempt read replies with `head -c 512`, which blocked waiting for more bytes and then lost its
buffered output when `timeout` killed it. A second attempt put `2>/dev/null` on the `exec` that opened the socket,
which silently redirected the shell's stderr for the rest of the run.
**Solution:** Read with `dd bs=4096 count=1`, which returns after one datagram or segment. Keep the shell's stderr
alone and classify failures from the errno text of a second send or of the connect.

**Observation:** Baseline from this sandbox, all over the current firewall:

- UDP/53 and TCP/53 to `127.0.0.11` both answer. `example.com` A returns two answers, TXT returns 98 bytes, and a
  random label under `example.com` returns `NXDOMAIN`, so the query reached beyond the host. `proxy` resolves
- Bridge gateway `172.22.0.1`: UDP/53 times out, TCP/53 is refused. The gateway is reachable through rule 5 and
  nothing listens on TCP/53 there
- Lima gateway `192.168.5.1`, `8.8.8.8` on 53, and `1.1.1.1` on 853 are all rejected by the firewall. UDP sends
  fail with `Operation not permitted`; TCP connects fail with `No route to host`. Those two strings are the firewall's
  signature and let the probe tell a `REJECT` apart from a missing listener or a silent drop

**Learning:** `NXDOMAIN` for a random label under a DNSSEC-signed zone is not by itself proof the authoritative
server saw the label, because aggressive NSEC caching can synthesize it. The end-to-end demonstration needs a capture
at the host's egress as well.
