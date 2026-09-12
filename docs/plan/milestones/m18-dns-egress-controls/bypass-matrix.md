# m18 bypass matrix

Status: baseline in progress. The in-container rows were measured on 2026-09-12 from this repo's dev sandbox on
Colima. The host-side rows (B3, B4, D2 through D4, H1 through H5) come from the first run of
`scripts/dns-egress-audit/run-audit.bash` and are marked pending until then.

Re-run with `scripts/dns-egress-audit/run-audit.bash --stage <stage>` on the Mac, or run `probe.bash` alone from a
sandbox shell for the in-container rows. `scripts/dns-egress-audit/README.md` has the procedure.

## Matrix

Result words are defined in the header of `probe.bash`. `*` means recorded but not compared.

| Id | Channel | Baseline | After m18.2 | After m18.3 | After m18.4 | Flipped by |
|----|---------|----------|-------------|-------------|-------------|------------|
| R1 | resolv.conf as Docker wrote it | `nameserver 127.0.0.11`, `ExtServers: [host(192.168.5.1)]` | * | * | * | info |
| R2 | default route | `172.22.0.1` on `eth0`, host network `172.22.0.0/16` | * | * | * | info |
| A1 | libc stub, public name | answered | not-found | not-found | not-found | m18.2 |
| A2 | libc stub, random label | not-found (upstream reached) | not-found | not-found | not-found | m18.2 via H1 |
| A3 | raw UDP/53 to `127.0.0.11`, A | answered, 2 answers | nxdomain | nxdomain | nxdomain | m18.2 |
| A4 | raw UDP/53, TXT | answered, 98 bytes | nxdomain | nxdomain | nxdomain | m18.2 |
| A5 | raw UDP/53, NULL | noerror-empty (forwarded) | nxdomain | nxdomain | nxdomain | m18.2 |
| A6 | raw UDP/53, 253-byte name | nxdomain, 271 bytes (forwarded) | nxdomain | nxdomain | nxdomain | m18.2 via H1 |
| A7 | raw TCP/53 to `127.0.0.11` | answered | nxdomain | nxdomain | nxdomain | m18.2 |
| A8 | service name `proxy` | answered | answered | answered | answered | control |
| B1 | UDP/53 to bridge gateway | timeout | rejected | rejected | rejected | m18.2 |
| B2 | TCP/53 to bridge gateway | conn-refused (reachable) | rejected | rejected | rejected | m18.2 |
| B3 | UDP/53 to a peer container | pending, expect reached | rejected | rejected | rejected | m18.2 |
| B4 | TCP/53 to a peer container | pending, expect reached | rejected | rejected | rejected | m18.2 |
| C1 | UDP/53 to `192.168.5.1` | rejected | rejected | rejected | rejected | control |
| C2 | TCP/53 to `192.168.5.1` | rejected | rejected | rejected | rejected | control |
| C3 | UDP/53 to `8.8.8.8` | rejected | rejected | rejected | rejected | control |
| C4 | TCP/53 to `8.8.8.8` | rejected | rejected | rejected | rejected | control |
| C5 | TCP/853 to `1.1.1.1` | rejected | rejected | rejected | rejected | control |
| D1 | DoH through proxy, unlisted host | proxy-403 | proxy-403 | proxy-403 | proxy-403 | control |
| D2 | DoH through proxy, host allowed | pending, expect http-200 | http-200 | http-200 | http-200 | residual |
| D3 | allowed name resolving to the bridge net | pending, expect http-502 | http-502 | http-502 | http-403 | m18.4 |
| D4 | allowed name resolving to loopback | pending, expect http-502 | http-502 | http-502 | http-403 | m18.4 |
| E1 | IPv6 on `eth0` | absent | absent | absent or present | same | m18.3 decides |
| E2 | UDP/53 to `2001:4860:4860::8888` | unreachable | unreachable | rejected when present | same | m18.3 |
| E3 | TCP/53 to `2001:4860:4860::8888` | unreachable | unreachable | rejected when present | same | m18.3 |
| E4 | TCP/853 to `2606:4700:4700::1111` | unreachable | unreachable | rejected when present | same | m18.3 |
| E5 | UDP/53 to `::1` | timeout | timeout | timeout | timeout | control |
| H1 | random label seen in the VM capture | pending, expect seen | not-seen | not-seen | not-seen | m18.2 |
| H2 | port 53 listeners inside the VM | pending | * | * | * | rule 5 decision |
| H3 | compose `dns:` semantics | pending | * | * | * | m18.2 design |
| H4 | `EnableIPv6` on the compose network | pending | * | * | * | m18.3 |
| H5 | `iptables -S`, `ip6tables -S` as root | pending | * | * | * | reference |

The same rows must hold in devcontainer mode. The runner takes `--container` for that; it is part of the `m18.2`
acceptance run rather than a separate row.

## End-to-end demonstration

The claim: a name the agent container looks up leaves the host as a DNS query, and answer data comes back. Anyone
with the sandbox running can reproduce it in three terminals.

1. On the Mac, capture DNS leaving the host. The interface is the one with the default route:

   ```bash
   sudo tcpdump -ni "$(route -n get 8.8.8.8 | awk '/interface:/{print $2}')" -l udp port 53
   ```

2. Inside the Colima VM, capture the embedded resolver's forward. Install `tcpdump` there first if needed:

   ```bash
   colima ssh -- sudo tcpdump -ni any -l udp port 53
   ```

3. Inside the sandbox, look up a label nobody has ever queried:

   ```bash
   getent ahosts "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n').example.com"
   ```

Expected: the VM capture shows `A? <label>.example.com.` heading for `192.168.5.1`, the Mac capture shows the same
name leaving toward the Mac's configured resolver, and `getent` prints nothing because the name does not exist. For
the return direction, run `bash scripts/dns-egress-audit/probe.bash --only A4` inside the sandbox: the TXT lookup
returns `answered` with the record bytes, so an attacker's zone can carry data back in.

The `NXDOMAIN` for a random label is not by itself proof that the authoritative server saw it. `example.com` is
DNSSEC-signed, and a validating resolver with aggressive NSEC caching can synthesize the answer. The captures are
the evidence; the `NXDOMAIN` is corroboration. `run-audit.bash` automates the VM capture as row H1 and prints the
label so the Mac capture can be started by hand.

## Findings

1. Recursive resolution is open in both directions. Raw UDP and TCP queries to the embedded resolver are answered
   for A and TXT, a NULL query is forwarded and comes back empty, and a 253-byte name is forwarded and comes back
   `NXDOMAIN`. Nothing about the query is filtered.
2. The forward to the upstream does not cross the container's firewall. Docker's `resolv.conf` comment marks the
   upstream as `host(192.168.5.1)`, and the container cannot reach that address itself: C1 and C2 are rejected while
   A1 succeeds. The `host(...)` marker is libnetwork's flag for an upstream it dials from the host network namespace
   rather than the container's. Consequence for `m18.2`: today's firewall cannot see the forward at all, so
   restricting port 53 only matters once the embedded resolver's upstream is a container address it dials from
   inside the container namespace. That is exactly what compose `dns:` on a user-defined network should produce, and
   H3 checks it.
3. No resolver answers on the bridge gateway over TCP; UDP to it times out with no ICMP error. H2 says whether
   anything listens on port 53 inside the VM at all.
4. IPv6 is absent on the compose network under Colima: no global address, no default route, and every IPv6 probe
   fails with `Network is unreachable`. H4 and H5 record whether the daemon could enable it and what `ip6tables`
   holds today.
5. The firewall's `REJECT` has a stable signature from inside the container: `Operation not permitted` on a UDP
   send and `No route to host` on a TCP connect. `m18.2` can use those in the self-test instead of timeouts.
6. Every direct channel in group C is already blocked. The open channels are the recursive path through the
   embedded resolver and, through rule 5, port 53 to anything on the host network (B1 through B4).
7. DoH to an unlisted host is refused by policy. DoH to an allowed host is open and stays open; that is the
   documented residual.

## Residual cases

- DNS-over-HTTPS or DNS-over-TLS to a host the policy allows. This milestone does not close it. D2 measures it so
  the docs in `m18.5` can state it plainly.
- The proxy container's own resolution is out of scope and untouched.

## Tools that resolve names themselves

Static inventory of network-using tools in the base image, the optional stacks, and the agent images. "Proxy-aware"
means the tool sends requests to `HTTP_PROXY` or `HTTPS_PROXY` and lets the proxy resolve the name. Anything that
is not proxy-aware will start failing with `NXDOMAIN` after `m18.2`. The dynamic check runs in `m18.2` against the
real sinkhole; entries marked "verify" are from documentation, not measurement.

| Tool | Where | Proxy-aware | Notes |
|------|-------|-------------|-------|
| `curl` | base | yes | honours the proxy environment variables |
| `git` | base, built against libcurl | yes | HTTPS remotes only; SSH is disabled |
| `gh` | base | yes | Go `ProxyFromEnvironment` |
| `apt` | base | yes | `configure-apt-proxy.sh` writes the Acquire proxy setting |
| `npm`, `npx` | node stack and every node-based agent image | yes | reads the proxy environment variables |
| Node `fetch`, `undici` | node-based agents | not by default | needs a dispatcher or `NODE_USE_ENV_PROXY`; per agent, verify |
| `pip`, `uv` | python stack, hermes | yes | verify `uv` |
| `go` | go stack | yes | module and checksum fetches honour the proxy variables |
| `cargo`, `rustup` | rust stack | yes | verify |
| `getent`, libc | everywhere | no | resolves directly; this is the path the sinkhole takes over |

## Pending

- Host-side rows B3, B4, H1 through H5 from the first `run-audit.bash` run.
- D2 through D4 from a run with `--policy-probes`.
- The devcontainer run with `--container`.
- The rule 5 decision point in `milestone.md`, once H2 is in.
