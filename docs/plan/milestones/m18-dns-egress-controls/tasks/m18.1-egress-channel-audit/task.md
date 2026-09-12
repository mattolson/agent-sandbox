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
| A2 | libc stub, random name | `getent ahosts <rand>.example.com` | nxdomain, upstream reached (spike) | m18.2 via H1 |
| A3 | raw UDP/53 to `127.0.0.11`, A | crafted packet | answered (spike) | m18.2 |
| A4 | raw UDP/53, TXT | qtype 16 | answered, 98 bytes (spike) | m18.2 |
| A5 | raw UDP/53, NULL | qtype 10 | | m18.2 |
| A6 | raw UDP/53, 253-byte name | 63-byte labels | | m18.2 |
| A7 | raw TCP/53 to `127.0.0.11` | length-prefixed packet | answered (spike) | m18.2 |
| A8 | service name `proxy` | A query | answered (spike) | control, must keep working |
| B1 | UDP/53 to bridge gateway | `172.22.0.1` | timeout (spike) | m18.2 |
| B2 | TCP/53 to bridge gateway | `172.22.0.1` | refused, reachable (spike) | m18.2 |
| B3 | UDP/53 to a peer container | listener on compose network | | m18.2 |
| B4 | TCP/53 to a peer container | listener on compose network | | m18.2 |
| C1 | UDP/53 to Lima gateway | `192.168.5.1`, the resolver's upstream | rejected (spike) | control |
| C2 | TCP/53 to Lima gateway | `192.168.5.1` | rejected (spike) | control |
| C3 | UDP/53 to public resolver | `8.8.8.8` | rejected (spike) | control |
| C4 | TCP/53 to public resolver | `8.8.8.8` | rejected (spike) | control |
| C5 | DoT to public resolver | `openssl s_client` to `1.1.1.1:853` | rejected (spike) | control |
| D1 | DoH through proxy, unlisted host | `curl -x proxy https://dns.google/resolve` | proxy-403 | control |
| D2 | DoH through proxy, host temporarily allowed | same, after a user policy edit | http-200 | none, residual |
| D3 | allowed host resolving to a private address | temporary rule for a wildcard-DNS name | | m18.4 |
| E1 | IPv6 presence | `ip -6 addr`, `ip -6 route` | none on `eth0` (spike) | m18.3 |
| E2 | UDP/53 to public resolver over IPv6 | `[2001:4860:4860::8888]` | | m18.3 |
| E3 | TCP/53 to public resolver over IPv6 | same | | m18.3 |
| E4 | DoT over IPv6 | `[2606:4700:4700::1111]:853` | | m18.3 |
| E5 | UDP/53 to `::1` | loopback only | | control |
| H1 | random label seen leaving the host | tcpdump in the VM and on the Mac | | m18.2 |
| H2 | listeners on port 53 inside the VM | `colima ssh -- sudo ss -lunp` | | informs rule 5 decision |
| H3 | compose `dns:` semantics on a user-defined network | override, then read `resolv.conf` | | informs m18.2 design |
| H4 | `EnableIPv6` on the compose network | `docker network inspect` | | informs m18.3 |
| H5 | agent `iptables` and `ip6tables` dump | `docker compose exec --user root` | | reference |
| M1 | full probe set in devcontainer mode | same runner, devcontainer stack | | m18.2 acceptance |

**Runner.** `run-audit.bash` runs on the Mac. It starts a throwaway `alpine` container named `dns-peer` on the
sandbox's compose network with busybox `nc` listening on UDP and TCP 53, passes its address to `probe.bash`, runs the
probes in the agent container, then collects H2 through H5 with `colima ssh` and `docker`. Output is a results TSV
plus a diff against `expected/<stage>.tsv`. Exit status reflects the diff, so a later task can run it as a gate.

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
runner diffs. The `m18.2` file must differ from baseline on A1, A3 through A7, B1 through B4, and H1; the `m18.3`
file on E2 through E4; the `m18.4` file on D3.

### Implementation Steps

- [ ] Write `probe.bash`: packet builder, UDP and TCP senders with errno classification, DoH and DoT probes, IPv6
      probes, TSV output, and a `--peer <addr>` flag for B3 and B4
- [ ] Write `run-audit.bash`: peer listener lifecycle, `docker compose exec` streaming, H2 through H5 collection,
      results file, expected-file diff, `--stage` and `--mode cli|devcontainer` flags
- [ ] Run the in-container probes from this sandbox and record the baseline for A, C, D1, and E
- [ ] Hand the runner to the maintainer for the host-side run: B3, B4, D2, D3, H1 through H5, and M1
- [ ] Write `bypass-matrix.md` with observed values, the demonstration procedure, and findings
- [ ] Write the four `expected/*.tsv` files
- [ ] Update `milestone.md`: resolve the rule 5 decision point from H2, record the `dns:` finding for `m18.2`, and
      the IPv6 default for `m18.3`
- [ ] Record the tool inventory in the matrix doc

### Open Questions

- Host-side steps cannot run from inside the sandbox: `docker`, `colima`, and `tcpdump` are out of reach. The plan
  splits execution so the in-container probes and the scripts are done here, and the maintainer runs
  `run-audit.bash` once on the Mac and commits the results file. Confirm that split is acceptable
- Is there a domain where a throwaway subdomain can be delegated to a temporary logging nameserver for the audit
  window? Without one, H1 is the demonstration and the aggressive-NSEC caveat is recorded
- D3 needs an allowed host whose answer is a private address. The cheapest option is a temporary rule for a public
  wildcard-DNS name such as `169.254.169.254.nip.io`, which leans on a third-party service. The alternative is to
  leave D3 to the proxy integration harness, which already rebinds hosts onto loopback, and drop it from the live
  matrix. Recommendation: the harness, since `m18.4` tests live there anyway
- The dynamic tool check is deferred to `m18.2`. Object if the static inventory is not enough for the rollout risk

## Outcome

### Acceptance Verification

- [ ] A checked-in matrix lists every probe, the observed result before any change, and the expected result after
- [ ] The demonstration of the query-name channel is reproducible by a second person from the write-up
- [ ] Every later task in this milestone has at least one probe that must flip from escape to blocked
- [ ] No probe depends on a nameserver or domain that outlives the audit

### Learnings

To be filled at completion.

### Follow-up Items

To be filled at completion.
