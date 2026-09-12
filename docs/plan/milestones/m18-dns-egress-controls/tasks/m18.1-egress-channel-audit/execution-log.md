# Execution Log: m18.1 - egress channel audit

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
