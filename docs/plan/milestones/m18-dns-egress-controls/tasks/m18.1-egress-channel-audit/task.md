# Task: m18.1 - egress channel audit

## Summary

Prove which outbound channels exist today and turn the result into a reusable bypass matrix.

## Scope

- Run each candidate channel from inside a current sandbox and record whether it escapes: `getaddrinfo` through
  `127.0.0.11`, raw UDP and TCP queries to `127.0.0.11`, to the Docker bridge gateway, to the Lima gateway the
  embedded resolver forwards to, to a public resolver, and to a peer container on the compose network; DNS-over-TLS
  on 853; DNS-over-HTTPS through the proxy; and the IPv6 equivalent of each
- Confirm the exfiltration path end to end, so the finding is a demonstration and not an inference
- Record whether the embedded resolver is reachable over TCP as well as UDP, and what it does with `TXT`, `NULL`, and
  a maximum-length name
- Check whether the Colima VM's bridge gateway runs a resolver the agent can reach directly, since rule 5 of
  `init-firewall.sh` allows the host network in both directions
- Determine whether the compose network has IPv6 enabled by default on Colima, and what `init-firewall.sh` leaves
  unprotected when it does
- Establish what compose `dns:` does on a user-defined network, because the `m18.2` design depends on it
- Inventory which bundled tools resolve names themselves rather than handing them to the proxy
- Package the probes as a script that can be re-run after each later task, with expected results per stage

## Acceptance Criteria

- [ ] A checked-in matrix lists every probe, the observed result before any change, and the expected result after
- [ ] The demonstration of the query-name channel is reproducible by a second person from the write-up
- [ ] Every later task in this milestone has at least one probe that must flip from escape to blocked
- [ ] No probe depends on a nameserver or domain that outlives the audit

## Applicable Learnings

- Environment-variable proxy configuration is advisory; network-level enforcement is what counts. The probes send raw
  packets from bash sockets as well as going through libc and `curl`, so a control that only covers `getaddrinfo`
  shows up as a gap rather than a pass
- Integration coverage catches wiring that unit tests miss. The runner drives a real stack on Colima, in both CLI and
  devcontainer mode, not a mock
- The firewall self-test's negative check is the model: every probe has a concrete expected failure signature, not a
  generic "did not work"
- Sudoers restricts the `dev` user to three scripts, so iptables state cannot be read from inside the container. Rule
  inspection is a host-side step through `docker compose exec --user root`
- The devcontainer path has historically diverged from the compose path. The same probe set runs in both modes

## Plan

### Files Involved

- `scripts/dns-egress-audit/probe.bash` (new): in-container probes. Bash, coreutils, `curl`, `openssl`, and
  `iproute2` only, so it runs unchanged in every agent image. Emits one TSV line per probe
- `scripts/dns-egress-audit/run-audit.bash` (new): host-side runner. Starts a peer listener on the compose network,
  streams `probe.bash` into the agent container over `docker compose exec`, collects the host-side facts, writes a
  timestamped results file, and diffs it against an expected file for the requested stage
- `scripts/dns-egress-audit/expected/{baseline,after-m18.2,after-m18.3,after-m18.4}.tsv` (new): the expected result
  for every probe at each stage. These encode the "must flip" criterion so later tasks can check it mechanically
- `docs/plan/milestones/m18-dns-egress-controls/bypass-matrix.md` (new): the matrix, the end-to-end demonstration
  procedure, the findings, and the residual cases
- `docs/plan/milestones/m18-dns-egress-controls/milestone.md`: record findings that change the scope of `m18.2` and
  `m18.3`, and resolve the decision point about rule 5
- `docs/plan/learnings.md`: at completion

### Approach

**Probe mechanics.** The images carry no `dig`, `nslookup`, `nc`, or `python3`, so `probe.bash` builds DNS query
packets by hand and sends them through bash's `/dev/udp` and `/dev/tcp` redirections. A planning spike from this
sandbox confirmed the approach and settled two details: the reply must be read with a single `dd` read rather than
`head`, which blocks waiting for more bytes, and the failure classes are distinguishable by errno text. `EPERM` on a
UDP send and `No route to host` on a TCP connect are the firewall's `REJECT`; `Connection refused` means the address
is reachable and nothing listens; a timeout is a silent drop. The result vocabulary is `answered`, `nxdomain`,
`servfail`, `refused`, `rejected`, `timeout`, `unreachable`, `proxy-403`, and `http-<code>`.

**Probe set.** Each probe has an id, a channel, and the task that must flip it. Baseline values marked `spike` were
observed during planning from this sandbox; the rest are measured during execution.

| Id | Channel | Method | Baseline | Flipped by |
|----|---------|--------|----------|------------|
| A1 | libc stub, public name | `getent ahosts example.com` | answered (spike) | m18.2 |
| A2 | libc stub, random name | `getent ahosts <rand>.example.com` | not-found, upstream hit (spike) | m18.2 via H1 |
| A3 | raw UDP/53 to `127.0.0.11`, A | crafted packet | answered (spike) | m18.2 |
| A4 | raw UDP/53, TXT | qtype 16 | answered, 98 bytes (spike) | m18.2 |
| A5 | raw UDP/53, NULL | qtype 10 | | m18.2 |
| A6 | raw UDP/53, 253-byte name | 63-byte labels | | m18.2 |
| A7 | raw TCP/53 to `127.0.0.11` | length-prefixed packet | answered (spike) | m18.2 |
| A8 | service name `proxy` | A query | answered (spike) | control, must keep working |
| B1 | UDP/53 to bridge gateway | `172.22.0.1` | timeout (spike) | m18.2 |
| B2 | TCP/53 to bridge gateway | `172.22.0.1` | refused, reachable (spike) | m18.2 |
| B3 | UDP/53 to a peer container | python responder on the compose network | | m18.2 |
| B4 | TCP/53 to a peer container | python responder on the compose network | | m18.2 |
| C1 | UDP/53 to Lima gateway | `192.168.5.1`, the resolver's upstream | rejected (spike) | control |
| C2 | TCP/53 to Lima gateway | `192.168.5.1` | rejected (spike) | control |
| C3 | UDP/53 to public resolver | `8.8.8.8` | rejected (spike) | control |
| C4 | TCP/53 to public resolver | `8.8.8.8` | rejected (spike) | control |
| C5 | DoT to public resolver | `openssl s_client` to `1.1.1.1:853` | rejected (spike) | control |
| D1 | DoH through proxy, unlisted host | `curl -x proxy https://dns.google/resolve` | proxy-403 | control |
| D2 | DoH through proxy, host temporarily allowed | same, after a user policy edit | http-200 | none, residual |
| D3 | allowed name resolving into the bridge network | `proxy` allowed temporarily, `http://proxy:9/` | | m18.4 |
| D4 | allowed name resolving to loopback | `localhost` allowed temporarily, `http://localhost:9/` | | m18.4 |
| E1 | IPv6 presence | `ip -6 addr`, `ip -6 route` | none on `eth0` (spike) | m18.3 |
| E2 | UDP/53 to public resolver over IPv6 | `[2001:4860:4860::8888]` | | m18.3 |
| E3 | TCP/53 to public resolver over IPv6 | same | | m18.3 |
| E4 | DoT over IPv6 | `[2606:4700:4700::1111]:853` | | m18.3 |
| E5 | UDP/53 to `::1` | loopback only | | control |
| H1 | random label seen leaving the host | tcpdump in the VM, Mac capture by hand | | m18.2 |
| H2 | listeners on port 53 inside the VM | `colima ssh -- sudo ss -lunp` | | informs rule 5 decision |
| H3 | compose `dns:` semantics on a user-defined network | override, then read `resolv.conf` | | informs m18.2 design |
| H4 | `EnableIPv6` on the compose network | `docker network inspect` | | informs m18.3 |
| H5 | agent `iptables` and `ip6tables` dump | `docker compose exec --user root` | | reference |

**Runner.** `run-audit.bash` runs on the Mac. It starts a throwaway `python:3-alpine` container on the sandbox's
compose network running a small DNS responder that answers every A query with `203.0.113.1` and logs each name,
passes its address to `probe.bash`, runs the probes in the agent container, then collects H1 through H5 with
`colima ssh` and `docker`. The responder replaced the original `nc` idea because a real reply makes B3 and B4
conclusive and lets H3 show where a forwarded query went. Output is a results TSV plus a diff against
`expected/<stage>.tsv`. Exit status reflects the diff, so a later task can run it as a gate. Devcontainer mode is
the same run with `--container` pointed at the VS Code container.

**End-to-end demonstration.** The in-container proof is A2 plus A4: a never-before-seen label returns `NXDOMAIN`,
and a TXT lookup returns data, so both directions work. `NXDOMAIN` alone is not airtight, because a validating
resolver with aggressive NSEC caching can synthesize it for a signed zone without asking the authoritative server.
The write-up therefore pairs it with H1: `tcpdump -ni any udp port 53` inside the Colima VM shows the embedded
resolver forwarding the random label to `192.168.5.1`, and the same capture on the Mac shows it leaving the host.
A second person reproduces this with two terminals and one `getent` call. If a domain can be delegated to a
temporary logging nameserver for the audit window, the runner accepts it as an optional stronger target and the
delegation is removed afterwards. Nothing in the checked-in probes references it.

**Compose `dns:` check (H3).** On a user-defined network Docker keeps `/etc/resolv.conf` pointed at `127.0.0.11` and
treats `dns:` as the embedded resolver's upstream list. If that holds, `m18.2` does not need a sinkhole that forwards
service names anywhere: the embedded resolver keeps answering service names from IPAM and forwards everything else to
the sinkhole, which answers `NXDOMAIN`. That also means a sidecar cannot forward to `127.0.0.11`, since that address
is per-container loopback. The probe adds `dns: [<proxy ip>]` in `user.override.yml`, recreates the stack, and reads
the `ExtServers` and `Overrides` lines Docker writes into `resolv.conf`.

**IPv6 (E1 through E5, H4, H5).** The spike shows no IPv6 address or route on `eth0`, so the expected baseline is
`unreachable` for every IPv6 probe and an empty `ip6tables` ruleset. The matrix records that as "unfiltered but
unavailable" so `m18.3` chooses between asserting it off and filtering it.

**Tool inventory.** Static in this task: for each network-using tool in the base and agent images, record whether it
honours `HTTP_PROXY` and `HTTPS_PROXY` or resolves names itself, from its documentation and the per-agent docs. The
dynamic check belongs in `m18.2`, where the real sinkhole exists to run it against.

**Matrix and expectations.** `bypass-matrix.md` holds the table above with observed values filled in, the
demonstration procedure, and the findings. The `expected/*.tsv` files hold the same expectations in the form the
runner diffs. The `m18.2` file must differ from baseline on A1, A3 through A5, A7, B1 through B4, and H1; the `m18.3`
file on E2 through E4 when IPv6 is present; the `m18.4` file on D3 and D4.

### Implementation Steps

- [x] Write `probe.bash`: packet builder, UDP and TCP senders with errno classification, DoH and DoT probes, IPv6
      probes, TSV output, and a `--peer <addr>` flag for B3 and B4
- [x] Write `run-audit.bash`: peer responder lifecycle, `docker exec` streaming, H1 through H5 collection,
      results file, expected-file diff, `--stage` and `--container` flags
- [x] Run the in-container probes from this sandbox and record the baseline for A, C, D1, and E
- [x] Maintainer runs `run-audit.bash` on the Mac: B3, B4, H1 through H5 measured; results directory committed
- [x] D2 through D4 taken from the sandbox after the temporary policy entries went live
- [x] Fix the runner for macOS awk, which reserves `exp` as a function name
- [x] Write `bypass-matrix.md` with observed values, the demonstration procedure, and findings
- [x] Write the four `expected/*.tsv` files
- [x] Update `milestone.md`: resolve the rule 5 decision point from H2, record the `dns:` finding for `m18.2`, and
      the IPv6 default for `m18.3`
- [x] Record the static tool inventory in the matrix doc

### Open Questions

Resolved on 2026-09-12:

- Host-side steps: the maintainer runs `run-audit.bash` on the Mac from the scripts and README in
  `scripts/dns-egress-audit/`. In-container probes and all files are done from the sandbox
- No domain is available to delegate, so H1 (a tcpdump capture inside the Colima VM, plus an optional capture on the
  Mac) is the end-to-end demonstration. The aggressive-NSEC caveat is recorded in the matrix doc
- The m18.4 probe stays in the live matrix without a third-party service: D3 and D4 temporarily allow the names
  `proxy` and `localhost`, which resolve into the bridge network and to loopback respectively. The renderer accepts
  dot-less hosts
- The dynamic tool check is deferred to `m18.2`; the matrix carries a static inventory

Resolved by the host run:

- B1's `timeout` is a missing listener with the ICMP error suppressed. H2 shows nothing bound to the gateway
  address on port 53; the VM's `dnsmasq` binds `192.168.5.1` and loopback only

## Outcome

### Acceptance Verification

- [x] A checked-in matrix lists every probe, the observed result before any change, and the expected result after.
      `bypass-matrix.md` plus `expected/*.tsv`, every row observed in CLI mode
- [x] The demonstration of the query-name channel is reproducible by a second person from the write-up. The
      three-terminal procedure is in the matrix doc; the checked-in VM capture shows the label at each hop
- [x] Every later task in this milestone has at least one probe that must flip from escape to blocked. `m18.2`:
      A1, A3 through A5, A7, B1 through B4, H1. `m18.3`: E2 through E4, with IPv6 enabled for the run. `m18.4`:
      D3 and D4
- [x] No probe depends on a nameserver or domain that outlives the audit. `example.com` is used read-only as a
      public zone; the peer responder is a throwaway container; the captures are local

### Learnings

- On a user-defined Docker network the stub is always `127.0.0.11`; compose `dns:` sets the embedded resolver's
  upstream list. Upstreams marked `host(...)` are dialed from the host namespace and bypass the container's
  firewall; container-address upstreams are dialed from the container and do not
- Bash can send and receive raw UDP and TCP through `/dev/udp` and `/dev/tcp`. Read replies with one
  `dd bs=4096 count=1`, capture open errors with `{ exec 3<>...; } 2>file`, and classify the firewall's `REJECT`
  by errno: `EPERM` on a UDP send, `EHOSTUNREACH` on a TCP connect
- A proxy 403 to a `CONNECT` request has no body and surfaces as curl exit 56; `%{http_connect}` shows it
- Host-side scripts run on macOS tools. BSD awk reserves built-in function names such as `exp` as identifiers,
  and the first host run failed on exactly that. Test them on the Mac or avoid those names
- The partial run still produced every row because the results file is written before the comparison. Keep
  collection and evaluation separate so a bug in one does not cost the other
- `curl` honours `NO_PROXY` even with an explicit `-x`; a probe that must traverse the proxy to a name on that
  list needs `--noproxy ''`
- A single-file bind mount pins the inode. A reload that re-reads the file can report success while reading
  content the host replaced minutes ago

### Follow-up Items

- `m18.2` must pick between the `dns:` upstream design (fixed sinkhole address, NAT restore stays) and the
  DNAT-at-init design (dynamic address, sinkhole forwards service names to its own embedded resolver). The
  milestone plan now carries both
- `m18.3` must enable IPv6 on the compose network for its audit run
- Propose a troubleshooting entry: the proxy's single-file bind mount of `user.policy.yaml` pins the inode, so
  editors that save by rename and `git checkout` make `agentbox proxy reload` re-render stale content while
  reporting `applied`. Restart the proxy, or consider mounting the policy directory instead of single files
- The devcontainer run is part of the `m18.2` acceptance rather than this task
