# Task: m18.3 - ipv6 egress parity

## Summary

Apply the same default-deny posture to IPv6 so the sinkhole cannot be stepped around over a second address family.

## Scope

From the milestone plan, with the adjustments proposed under Approach and listed as open questions:

- Extend `init-firewall.sh` to program `ip6tables` alongside `iptables`: default-deny policies, loopback limited to
  `::1`, established and related. Decided 2026-09-17: no host-network exception and no port 53 exception over IPv6,
  because the agent reaches the proxy and the sinkhole over IPv4 by construction
- Handle the case where the kernel or image lacks `ip6tables` support: fail closed with a clear message when IPv6 is
  present on the interface, continue with an explicit message when it is absent
- Decide whether to disable IPv6 on the compose network instead, and record why. Decided 2026-09-17: filter, and
  treat Docker's default of no IPv6 as the common case the self-test names rather than something the firewall
  relies on
- Add the IPv6 probes from `m18.1` to the firewall self-test
- Enable IPv6 on the compose network for the `after-m18.3` audit run in both modes, and tighten the expected file so
  the E rows must flip when IPv6 is present
- Map the IPv6 reject errno in `probe.bash` so E2 through E4 can read `rejected`
- Rollout is image-only, base image only: `agentbox bump` then `agentbox up`. Changelog entry
- Out of scope: user docs and the skill note, which `m18.5` writes; the proxy container's own IPv6 use; any compose
  or template change

## Acceptance Criteria

- [ ] With IPv6 available on the network, every IPv6 probe from the audit is blocked
- [ ] With IPv6 unavailable, container start still succeeds and the self-test says so explicitly
- [ ] No IPv4 behavior changes

## Applicable Learnings

- Runtime sync writes the managed compose layers only when they are missing, so a design that needs a compose change
  reaches existing projects only through `agentbox init`. An image-only design rolls out through `agentbox bump`
  alone (m18.2). The same constraint rules out `sysctls:` on the agent service or `enable_ipv6: false` on the network
  as the control
- Entrypoint scripts must be idempotent. `init-firewall.sh` re-runs safely in a live sandbox and re-verifies its
  self-tests; that is the repair path, and the IPv6 block must keep it so (m18.2)
- The firewall's `REJECT` shows up as `EPERM` on a UDP send and `EHOSTUNREACH` on a TCP connect over IPv4 (m18.1).
  Over IPv6 the kernel converts an ICMPv6 administratively-prohibited error to `EACCES` (`Permission denied`) on a
  TCP connect; `errno_result` in `probe.bash` does not map that string, so E3 and E4 would read `error` instead of
  `rejected`. To confirm on the host
- An expected file written at planning time needs a pass against the final rule order (m18.2). The current
  `after-m18.3.tsv` accepts `unreachable` for E2 through E4, which an unfiltered stack with IPv6 absent also
  produces; the run that proves the flip must not be able to pass that way
- Keep security invariants attached to the construct that enforces them (milestone). The firewall is the construct
  that denies IPv6 egress; the sinkhole's AAAA answers are not a control and need not change
- Facts from this sandbox on the rebuilt `m18.2` stack: `disable_ipv6` is 1 on `eth0` and 0 on `all`, which is what
  Docker sets on an interface whose network has no IPv6; `lo` keeps `::1`; `ip -6 route` is empty; the latest
  audit's `ip6tables -S` shows ACCEPT policies with no rules (H5). IPv6 is unfiltered but unreachable, as `m18.1`
  found
- mitmproxy binds dual-stack when `listen_host` is empty: TCP through `asyncio.start_server`, and for UDP a second
  server on `::` beside `0.0.0.0` (`mitmproxy/proxy/mode_servers.py`). The sinkhole is reachable over IPv6 wherever
  the proxy container has an address, so nothing in `images/proxy/` changes
- The sinkhole answers AAAA for an allowed name through `getaddrinfo` (`dns_sinkhole.py`). With IPv6 on the network,
  `proxy` gains an AAAA record and a client may try that address first; under the proposed rules the attempt is
  rejected at once and the client falls back to IPv4

## Plan

### Files Involved

- `images/base/init-firewall.sh`: the IPv6 availability check, rules, self-tests, and messages, plus the
  `getent ahostsv4` fix to `resolve_proxy`
- `images/base/entrypoint.sh`: only if the fail-closed banner needs a line naming IPv6
- `scripts/dns-egress-audit/probe.bash`: `errno_result` gains the IPv6 reject signature
- `scripts/dns-egress-audit/expected/after-m18.3.tsv`: E1 `present`, E2 through E4 `rejected`
- `scripts/dns-egress-audit/README.md`: how to enable IPv6 on the compose network for the run
- `docs/plan/milestones/m18-dns-egress-controls/bypass-matrix.md`: the observed after-m18.3 values for the E rows
  and H5, and the pending list
- `.agent-sandbox/compose/user.override.yml`: `enable_ipv6: true` on the default network for this repo's dev
  runtime, decided yes on 2026-09-17. Applied on the host: `.agent-sandbox/` is mounted read-only in the sandbox
- `CHANGELOG.md`: an `[Unreleased]` entry that says rebuilt images are required
- `docs/plan/milestones/m18-dns-egress-controls/milestone.md`: record the choice under `m18.3`

No change under `internal/`, `internal/embeddata/templates/`, or `images/proxy/`.

### Approach

**Design choice.** Three shapes were on the table.

1. Disable IPv6 rather than filter it. Docker already does this by default: `EnableIPv6=false` on the network and
   `disable_ipv6=1` on `eth0`. Turning the default into a guarantee needs either `sysctls:` on the agent service or
   an explicit network definition, both managed-layer changes that only `agentbox init` propagates, and a runtime
   `sysctl -w` from the firewall script is expected to fail because Docker mounts `/proc/sys` read-only. It also
   fails the milestone's first criterion: a user who enables IPv6 for a sidecar would be unfiltered. Rejected.
2. Full parity. Mirror the IPv4 rule set in `ip6tables`: a DNAT from port 53 to the sinkhole on the proxy's IPv6
   address, an accept for the host network's IPv6 prefix, and the ICMPv6 neighbour-discovery types without which an
   IPv6 link does not work under a default-deny `OUTPUT`. Every one of those rules is a second copy of an IPv4 path
   with no consumer: `resolv.conf` names the proxy's IPv4 address, the sinkhole exception is IPv4, and `HTTPS_PROXY`
   is a name the sinkhole answers with both records, of which the IPv4 one is the one that connects. More rules to
   get right, and a run with IPv6 enabled is the only way to test any of them.
3. Deny all IPv6 except loopback and established or related traffic. Four rules plus three policies. IPv6 inside the
   sandbox becomes loopback-only. The sinkhole keeps answering AAAA; a client that tries the IPv6 address first gets
   an immediate reject and falls back.

This task takes option 3, subject to open question 1. The milestone scope listed the host-network and port 53
exceptions for IPv6; the deviation and the reasoning above go into the milestone's Changes section once approved.

**Firewall.** A new block after step 9, so the IPv4 rules are complete before IPv6 is touched.

- No learn-before-flush step for IPv6, unlike step 1 for `127.0.0.11`. The loopback rules admit `::1` only
  (`-o lo -d ::1` out, `-i lo -d ::1` in), so an address Docker might add to `lo` for its own resolver is denied
  without the script knowing it, on a first start and on a re-run alike. The cost is local delivery to the
  container's own global IPv6 address, which nothing in the sandbox uses. `ip6tables -t nat` is still flushed
- Detect presence the way E1 does: `ip -6 addr show dev "$DEFAULT_IF" scope global` prints an address, or not. Read
  `/proc/sys/net/ipv6/conf/$DEFAULT_IF/disable_ipv6` for the message only
- Availability: `ip6tables -S` succeeds, or not. Unavailable and present: print
  `ERROR: IPv6 is present on eth0 but ip6tables is unavailable; refusing to start with IPv6 unfiltered` and exit 1.
  Unavailable and absent: print `IPv6: absent on eth0 and ip6tables unavailable; nothing to filter` and continue.
  Available: install the rules whether or not IPv6 is present, so the ruleset is the same on every start and H5
  reads the same in both cases
- Rules, in order: accept `lo` in and out for `::1`; accept established and related in and out; set `INPUT`,
  `FORWARD`, and `OUTPUT` to `DROP`; end `OUTPUT` with `REJECT --reject-with icmp6-adm-prohibited` so a blocked
  attempt fails at once instead of timing out. Flush the `filter` table first, and the `nat` and `mangle` tables
  where the kernel has them
- `resolve_proxy` and the audit's `PROXY_ADDR` switch from `getent hosts` to `getent ahostsv4`. `getent hosts`
  prefers the AAAA record, so on a network with IPv6 the firewall would have found no IPv4 address for the proxy
  and refused to start, and the audit's S rows would have targeted the IPv6 address
- Self-tests, after the existing four. Present: a UDP query to `2001:4860:4860::8888` on port 53 must be
  `rejected`, and a TCP connect to the same address on 53 must fail without waiting for a timeout; either outcome
  otherwise is a `FAIL` that exits 1. Absent: one `PASS` line that names the state, for example
  `PASS: IPv6 absent on eth0 (disable_ipv6=1); ip6tables default-deny installed`, or the unavailable variant. That
  line is the explicit statement the second criterion asks for. Both branches, when `lo` has `::1`, send one UDP
  datagram to `[::1]:9`, which must succeed, so a rule that closes loopback by accident is caught. `dns_rcode`
  already prints `rejected`
  and `unreachable` from the errno of the send and the open, and bash resolves a bare IPv6 literal in
  `/dev/udp/<address>/<port>`, which the audit relies on today
- `entrypoint.sh` keeps its "already initialized" check on the IPv4 `OUTPUT` policy. The script is idempotent and
  a container is recreated when its image changes, so a container with IPv4 rules and no IPv6 rules does not occur

**Audit.** `errno_result` maps `Permission denied` to `rejected`. `after-m18.3.tsv` expects E1 `present` and E2
through E4 `rejected`, so a run with IPv6 absent fails it on purpose; E5 stays `timeout|conn-refused|rejected`,
because loopback stays open and nothing listens on `[::1]:53`. The IPv6-absent case after this task is the
`after-m18.2` expectation set, and the README says which stage to run when. The README also carries the override
that enables IPv6 for the run:

```yaml
networks:
  default:
    enable_ipv6: true
```

If the daemon does not assign a unique-local prefix on its own (open question 4), the override needs an `ipam`
block with a `fd00::/8` subnet as well. Both modes share `user.override.yml`, so one edit covers the CLI and
devcontainer runs. Changing a network's options needs `agentbox down` before `agentbox up`; compose will not
recreate an existing network in place.

**Rollout.** Base image only. A new agent image against an old proxy image is unaffected; nothing in the IPv6 block
touches the proxy. The changelog entry says rebuilt images are required.

**Testing.** The firewall has no unit harness and `shellcheck` is not in the dev image or CI. From this sandbox the
script cannot be run: `sudo` allows only the installed copy and the `dev` user lacks `NET_ADMIN`. The maintainer's
sequence is `make setup`, then `agentbox up` with IPv6 off to see the absent-path self-test line and a clean
`--stage after-m18.2` run, which is the "no IPv4 behavior changes" check; then the override, `agentbox down`,
`agentbox up`, and `--stage after-m18.3` in CLI mode and with `--container` against the devcontainer. The H5 dump
in each run records the installed IPv6 rules.

### Implementation Steps

- [x] Add the IPv6 block to `init-firewall.sh`: the availability check with both messages, the `::1`-only loopback
      rules, the self-tests, and the `getent ahostsv4` fix to `resolve_proxy`
- [x] Extend `errno_result`, switch `PROXY_ADDR` to `ahostsv4`, tighten `after-m18.3.tsv`, add the README section
      on enabling IPv6, and note the change in the bypass matrix
- [x] Write the changelog entry and record the design choice in the milestone plan
- [x] Maintainer adds `networks: default: enable_ipv6: true` to `.agent-sandbox/compose/user.override.yml` on the
      host; the directory is read-only inside the sandbox
- [ ] Maintainer rebuilds with `make setup`, runs `agentbox up` with IPv6 off, confirms the absent-path line in the
      banner, and runs the audit at `--stage after-m18.2` to show IPv4 is unchanged
- [ ] Maintainer enables IPv6 in `user.override.yml`, runs `agentbox down` and `agentbox up`, and runs the audit at
      `--stage after-m18.3` in CLI mode and against the devcontainer. Record the Docker Engine version, whether a
      prefix was assigned automatically, and what Docker did for DNS over IPv6 (`resolv.conf`, `ip6tables -t nat`,
      listeners in a throwaway container)
- [ ] Verify each acceptance criterion, capture learnings, and note follow-ups for `m18.5`

### Open Questions

1. Resolved 2026-09-17: deny-all IPv6 (option 3). A sidecar reachable only over IPv6 is not a case to support
2. Resolved 2026-09-17: this repo's checked-in `user.override.yml` keeps `enable_ipv6: true`, so development
   exercises the IPv6 path every day
3. Resolved 2026-09-17: the sinkhole keeps answering AAAA. The firewall is the control, and a proxy change would
   widen the rollout
4. Resolved 2026-09-17: Docker Engine 29.2.1 on Colima, which assigns a unique-local prefix when no subnet is
   given. The override carries no `ipam` block
5. What Docker does for DNS on an IPv6-enabled network: whether `resolv.conf` gains an IPv6 nameserver, whether
   `ip6tables -t nat` holds a redirect, and what the embedded resolver listens on. No longer changes the code, since
   loopback admits `::1` only, but worth recording from the run for the decision record `m18.5` writes
6. Resolved 2026-09-27: an IPv6 reject on a TCP connect is `EACCES` (`Permission denied`), as expected

## Outcome

### Acceptance Verification

_Pending._

### Learnings

_Pending._

### Follow-up Items

_Pending._
