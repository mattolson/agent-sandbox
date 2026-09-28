# m18 bypass matrix

Status: baseline complete for CLI mode, measured on 2026-09-12 from this repo's dev sandbox on Colima. The
in-container rows were run from the sandbox, the host-side rows by `run-audit.bash` on the Mac, and D2 through D4
from a sandbox shell after the temporary policy entries went live. The raw run is checked in under
`scripts/dns-egress-audit/results/baseline-20260912-121839/`. The devcontainer run belongs to the `m18.2`
acceptance. The after-m18.2 column is confirmed for both modes as of 2026-09-13; those runs are working files
under `results/after-m18.2-20260913-161555/` (CLI) and `results/after-m18.2-20260913-162638/` (devcontainer).
The after-m18.3 column is confirmed for CLI mode as of 2026-09-27, with IPv6 enabled on the compose network
(`results/after-m18.3-20260927-155350/`, a working file) and for devcontainer mode on the same day
(`results/after-m18.3-20260927-160744/`). From the CLI run on,
H1 carries a positive control: a separate `ctl-` label resolved through Docker's resolver from a throwaway
container during the capture, which must appear in the capture for `not-seen` to count. The after-m18.4 column is
confirmed for both modes as of 2026-09-27, run with `--policy-probes` and IPv6 on
(`results/after-m18.4-20260927-172036/` CLI, `results/after-m18.4-20260927-172535/` devcontainer).

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
| A3 | raw UDP/53 to `127.0.0.11`, A | answered, 2 answers | rejected | rejected | rejected | m18.2 |
| A4 | raw UDP/53, TXT | answered, 98 bytes | rejected | rejected | rejected | m18.2 |
| A5 | raw UDP/53, NULL | noerror-empty (forwarded) | rejected | rejected | rejected | m18.2 |
| A6 | raw UDP/53, 253-byte name | nxdomain, 271 bytes (forwarded) | rejected | rejected | rejected | m18.2 via H1 |
| A7 | raw TCP/53 to `127.0.0.11` | answered | rejected | rejected | rejected | m18.2 |
| A8 | raw UDP/53 to `127.0.0.11`, A `proxy` | answered | rejected | rejected | rejected | m18.2; S3 is the control |
| A9 | raw UDP to the embedded resolver's real port | answered | rejected | rejected | rejected | m18.2 |
| A10 | raw TCP to the embedded resolver's real port | answered | rejected | rejected | rejected | m18.2 |
| B1 | UDP/53 to bridge gateway | timeout | rejected | rejected | rejected | m18.2 |
| B2 | TCP/53 to bridge gateway | conn-refused (reachable) | rejected | rejected | rejected | m18.2 |
| B3 | UDP/53 to a peer container | reached, peer logged the query | rejected | rejected | rejected | m18.2 |
| B4 | TCP/53 to a peer container | reached, peer logged the query | rejected | rejected | rejected | m18.2 |
| C1 | UDP/53 to the upstream, `192.168.5.1` | rejected | rejected | rejected | rejected | control |
| C2 | TCP/53 to the upstream, `192.168.5.1` | rejected | rejected | rejected | rejected | control |
| C3 | UDP/53 to `8.8.8.8` | rejected | rejected | rejected | rejected | control |
| C4 | TCP/53 to `8.8.8.8` | rejected | rejected | rejected | rejected | control |
| C5 | TCP/853 to `1.1.1.1` | rejected | rejected | rejected | rejected | control |
| D1 | DoH through proxy, unlisted host (`cloudflare-dns.com` from 2026-09-27; `dns.google` before) | proxy-403 | proxy-403 | proxy-403 | proxy-403 | control |
| D2 | DoH through proxy, host allowed | http-200, authority reached | http-200 | http-200 | http-200 | residual |
| D3 | allowed name resolving to the bridge net | http-502, port refused | http-502 | http-502 | guard-refused | m18.4 |
| D4 | allowed name resolving to loopback | http-502, both loopbacks refused | http-502 | http-502 | guard-refused | m18.4 |
| S1 | random label to `proxy:53` | timeout, no listener | nxdomain | nxdomain | nxdomain | m18.2 control |
| S2 | random label to `proxy:5353` | timeout, no listener | nxdomain | nxdomain | nxdomain | m18.2 control |
| S3 | `proxy` A to `proxy:53` | timeout, no listener | answered | answered | answered | m18.2 control |
| E1 | IPv6 on `eth0` | absent | absent | present (IPv6 enabled for the run) | same | m18.3 |
| E2 | UDP/53 to `2001:4860:4860::8888` | unreachable | unreachable | rejected | same | m18.3 |
| E3 | TCP/53 to `2001:4860:4860::8888` | unreachable | unreachable | rejected | same | m18.3 |
| E4 | TCP/853 to `2606:4700:4700::1111` | unreachable | unreachable | rejected | same | m18.3 |
| E5 | UDP/53 to `::1` | timeout | timeout | timeout | timeout | control |
| H1 | random label seen in the VM capture | seen, 6 packets, left on `eth0` | not-seen | not-seen | not-seen | m18.2 |
| H2 | port 53 listeners inside the VM | `dnsmasq` on `192.168.5.1` and loopback only | * | * | * | rule 5 decision |
| H3 | compose `dns:` semantics | upstream-only, dialed from the container | * | * | * | m18.2 design |
| H4 | `EnableIPv6` on the compose network | false, `172.22.0.0/16` only | * | * | * | m18.3 |
| H5 | `iptables -S`, `ip6tables -S` as root | 13 v4 rules; v6 ACCEPT policies, no rules | * | * | * | reference |

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
8. The full path of a query, from the VM capture (H1): the agent's stub sends to `127.0.0.11`; the embedded
   resolver, dialing from the VM's namespace, sends it over `lo` to `dnsmasq` on `192.168.5.1:53`; `dnsmasq`
   forwards it out `eth0` to `192.168.5.2:53`, Lima's host-side resolver, and from there the Mac's resolver takes
   it to the internet. The 253-byte name from A6 travelled the same path unmodified.
9. Compose `dns:` on a user-defined network is an upstream setting, not a replacement (H3). With `--dns` set to
   the peer, `resolv.conf` still says `nameserver 127.0.0.11`, the comment reads `ExtServers: [172.22.0.4]` with
   no `host(...)` marker and `Overrides: [nameservers]`, `proxy` still resolves from IPAM, and `example.com`
   came back as the peer's `203.0.113.1`. The peer's log shows the forwarded query arriving from the throwaway
   container's own address, so that forward crosses the container's firewall, unlike today's `host(...)` forward.
   Two consequences for `m18.2`: if it uses `dns:`, the `127.0.0.11` NAT rules must stay restored, and the
   sinkhole needs a fixed address because `dns:` takes IP addresses. The alternative is a DNAT at firewall init
   to the sinkhole's current address, with the sinkhole forwarding service names to its own embedded resolver.
10. The only resolver in the VM is `dnsmasq`, bound to `192.168.5.1`, `127.0.0.1`, `::1`, and the link-local
    IPv6 address on `eth0`, over UDP and TCP (H2). Nothing listens on the bridge gateway `172.22.0.1`, which is
    why B2 is refused and B1 times out. Rule 5 does not need narrowing for DNS; restricting port 53 within the
    host network to the resolver's address covers B1 through B4.
11. `ip6tables` works in the image and holds ACCEPT policies with no rules (H5), and the compose network has
    `EnableIPv6=false` (H4). IPv6 is unfiltered but unreachable. The `after-m18.3` run must enable IPv6 on the
    network, for example with `enable_ipv6: true` in a user override, or the E rows cannot flip.
12. The residual is real (D2). With `dns.google` allowed, a DoH lookup for the random label returned a JSON answer
    whose authority section names `example.com`'s nameservers, so the label reached the authoritative server
    through Google's resolver with nothing in the sandbox involved but an allowed HTTPS host. D1 read `http-200`
    in that state too while it also used `dns.google`, so a `--policy-probes` run could never pass it. Since
    2026-09-27 D1 queries `cloudflare-dns.com`, which the probe setup never allows, and reads `proxy-403` in every run.
13. The proxy dials wherever an allowed name points (D3, D4). `proxy` resolved to the proxy's own bridge address
    and `localhost` to both loopbacks; the proxy connected, got the port refused, and returned a 502 with the
    errno in the body. Nothing checks the address class before the connect. `m18.4` turns both into a refusal
    before the connect, with a distinct event.
15. Found while planning `m18.2`: the embedded resolver listens on a random high port on `127.0.0.11` (visible
    with `ss -lun` and `ss -ltn`), and the port-53 NAT rule only redirects to it. Raw queries to that port are
    answered and forwarded upstream exactly like port 53 (A9, A10). Dropping the NAT rules is therefore not
    enough; `m18.2` rejects all traffic to `127.0.0.11` ahead of the loopback allow rule, which is why the raw
    rows in the after-m18.2 column read `rejected` rather than `nxdomain`.
14. An operational finding from taking D2: the proxy mounts `user.policy.yaml` as a single-file bind mount, so an
    editor that saves by writing a new file and renaming it leaves the container attached to the old inode.
    `agentbox proxy reload` then re-renders the stale content and reports `applied`. `agentbox compose restart
    proxy` re-establishes the mount from the path. The README for the audit says restart, not reload, for this
    reason.
16. From the first after-m18.2 host run: two audit defects, no firewall defect. A8 was planned as `answered`, but it
    is a raw query to `127.0.0.11`, which the design rejects outright, so it flips with the other raw rows; S3
    carries the service-name control. And C1 and C2 read the upstream from the `ExtServers` comment in the
    agent's `resolv.conf`, which the firewall now rewrites, so the runner reads it from a throwaway container on
    the sandbox network and passes `--upstream`. Every other compared row matched on the first run.

## Residual cases

- DNS-over-HTTPS or DNS-over-TLS to a host the policy allows. This milestone does not close it. D2 measures it, and
  `docs/network.md` states it.
- The proxy container's own resolution is out of scope and untouched.
- Every compose service is reachable from the agent on any port; a service that forwards traffic is an egress path.
  Sidecars are trusted egress (raised in the #204 review, stated in `docs/network.md`).
- The address guard trusts the answers of the proxy container's resolver.

## Coverage

Each control in the milestone, what tests it automatically, and how to check it by hand. "Every start" means the
firewall's self-test, which refuses to start the container if the check fails. The manual procedures run on the host;
the audit rows come from `scripts/dns-egress-audit/run-audit.bash --stage after-m18.4 --policy-probes`, with IPv6
enabled on the compose network for the E rows.

| Control | Automated | Manual |
|---------|-----------|--------|
| Direct outbound refused | Every start: connect to `1.1.1.1` must fail | Audit C1-C5 |
| Docker's resolver refused, port 53 and its real port | None | Audit A3-A10 |
| DNS only to the sinkhole; 53 and 853 refused elsewhere, peers included | Every start: the negative lookup goes through the port-53 rewrite | Audit B1-B4, C1-C5 |
| Unknown names get `NXDOMAIN`, no query leaves the host | Every start: a random `.invalid` name must get `NXDOMAIN`; `test_dns_sinkhole.py` unit tests; integration `test_unknown_name_is_nxdomain_over_udp_and_tcp` | Audit A1, A2, S1, S2; H1 with its positive control |
| Allowed service names resolve | Every start: `proxy` must resolve through the sinkhole; integration `test_allowed_name_is_answered_with_addresses_and_ttl` | Audit S3 |
| Built-in resolver removed, unanswered queries fail closed | Integration `test_listener_starts_with_builtin_resolver_removed`; unit tests | None |
| `mitmdump` exits cleanly after DNS queries | Integration `test_shutdown_after_queries_exits_cleanly` | None |
| IPv6 refused except `::1` | Every start with IPv6 present: UDP and TCP 53 over IPv6 must be rejected, `::1` open | Audit E1-E4 with IPv6 enabled |
| Refuse to start with IPv6 present and no `ip6tables` | None | Procedure 1 below. Not yet run |
| New agent image refuses an old proxy image | None | Procedure 2 below. Run 2026-09-28: refused to start as expected |
| Address guard refuses each denied class | `test_address_guard.py` unit tests per class; integration `test_each_denied_class_is_refused_and_named` | Audit D3, D4 |
| The dial uses only checked answers | Invariant tests in both `test_address_guard.py` files, each confirmed by mutation | None |
| Guard refusals answer 403 on CONNECT and plain HTTP | Integration `test_invariant_refused_connect_gets_403_and_no_packet_reaches_the_address`, `test_allowed_name_resolving_to_loopback_is_refused_with_403` | Audit D3, D4 |
| IP-literal hosts not checked | Integration `test_ip_literal_hosts_are_not_checked`; every pre-existing integration test | None |
| DoH to an allowed host (residual) | None | Audit D2 records it |

Procedure 1, fail closed without `ip6tables`. With IPv6 enabled on the compose network, from the host:

```bash
AGENT=<agent container>
docker exec -u root "$AGENT" mv /usr/sbin/ip6tables /usr/sbin/ip6tables.off
docker exec -u root "$AGENT" /usr/local/bin/init-firewall.sh; echo "exit=$?"
# expect: ERROR: IPv6 is present (eth0 <address>) but ip6tables is unavailable.  exit=1
docker exec -u root "$AGENT" mv /usr/sbin/ip6tables.off /usr/sbin/ip6tables
docker exec -u root "$AGENT" /usr/local/bin/init-firewall.sh
```

The script stops before touching the IPv6 rules, but it has already flushed and rebuilt the IPv4 ones, so re-run it
after restoring `ip6tables`.

Procedure 2, version skew. In a scratch project, run the new agent image against the proxy image published from before
the sinkhole, `agentbox up`, and read the agent's log: it must stop with `ERROR: 'proxy' does not resolve through the
sinkhole` and the `FATAL: Firewall initialization failed!` banner that names `agentbox bump`.

## Tools that resolve names themselves

Network-using tools in the base image, the optional stacks, and the agent images. "Proxy-aware" means the tool sends
requests to `HTTP_PROXY` or `HTTPS_PROXY` and lets the proxy resolve the name. Anything that is not proxy-aware fails
with `NXDOMAIN` after `m18.2`; before it, the firewall already refused its direct connection, so only the error
changed. Measured on 2026-09-28 with `scripts/dns-egress-audit/tool-probe.bash` against the live sinkhole: in a hermes
image built on the node, python, and rust stacks, and in this repo's dev image for `go`. Rows marked "documented"
were not probed.

| Tool | Where | Proxy-aware | Notes |
|------|-------|-------------|-------|
| `curl` | base | yes | measured, 7.88.1 |
| `git` | base, built against libcurl | yes | measured, 2.50.1; HTTPS remotes only, SSH is disabled |
| `gh` | base | yes | documented: Go `ProxyFromEnvironment`; used through the proxy daily in `m17` |
| `apt` | base | yes | documented: `configure-apt-proxy.sh` writes the Acquire proxy setting |
| Python `urllib`, `pip` | python stack | yes | measured, Python 3.11.2 and pip 23.0.1 |
| `uv` | hermes | yes | measured, 0.11.21 |
| `npm`, `npx` | node stack and every node-based agent image | yes | measured, npm 10.9.9 |
| Node `fetch`, `undici` | node stack and node-based agent images | not by default | measured, Node 22.23.3: fails with `ENOTFOUND`. With `NODE_USE_ENV_PROXY=1` it uses the proxy, printing an "experimental" warning, and a refused host surfaces as `Request was cancelled.` rather than a 403 |
| `go` | go stack | yes | measured, 1.26.1 |
| `cargo` | rust stack | yes | measured, 1.98.1 |
| `rustup` | rust stack | yes | measured, 1.29.1, with a writable `RUSTUP_HOME`; the stack's own is root-owned, so rustup cannot write as the agent user at all |
| `getent`, libc | everywhere | no | resolves directly; this is the path the sinkhole takes over |
