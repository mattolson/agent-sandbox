# Task: m18.2 - dns sinkhole

## Summary

Give the agent container a resolver that answers compose service names and nothing else, and point the firewall at
it.

## Scope

Updated from the milestone plan after the `m18.1` audit and a planning spike:

- Run the sinkhole inside the existing proxy container as a mitmproxy DNS-mode addon on an unprivileged port. No
  new compose service, no compose template change, no scaffold change
- Serve only the names the stack needs: `proxy`, plus any exact names listed in `AGENTBOX_DNS_ALLOW` on the proxy
  service. Answer `NXDOMAIN` promptly for everything else, `NOERROR` with no records for non-address types on an
  allowed name, and fail closed with `SERVFAIL` if the addon ever leaves a query unanswered
- Never ask the proxy container's own resolver about a name outside the allowed set, because that resolver forwards
  unknown names upstream and would reopen the channel from the proxy side
- In `init-firewall.sh`: learn the proxy's address before flushing, stop restoring Docker's `127.0.0.11` NAT rules,
  reject `127.0.0.11` outright, rewrite port 53 to the proxy's sinkhole port with a `nat` `OUTPUT` DNAT, allow DNS
  only to the proxy, reject port 53 and 853 everywhere else, and point `/etc/resolv.conf` at the proxy. Keep the
  existing self-tests and add the DNS pair; move the negative connect test to an IP literal since names no longer
  resolve
- Add the sinkhole control rows to the audit and update the `after-m18.2` expectations to the chosen design
- Leave the proxy container's own resolution untouched
- Rollout is image-only: `agentbox bump` then `agentbox up`. Record the version-skew behaviour in the changelog
- Out of scope: user docs, troubleshooting, the skill note, and the decision record, which `m18.5` writes from the
  rationale recorded here; IPv6, which is `m18.3`

## Acceptance Criteria

- [ ] From the agent container, a lookup of a random label under a domain we control returns `NXDOMAIN` and no
      query reaches that domain's nameserver
- [ ] `curl -x http://proxy:8080 https://github.com` still succeeds, and an unlisted host still returns the proxy 403
- [ ] A direct query to a public resolver and a direct query to the bridge gateway both fail
- [ ] The firewall self-test fails the container start if either DNS assertion does not hold
- [ ] Both CLI mode and devcontainer mode pass the same assertions
- [ ] `go test ./...` and the proxy suite pass, and generated compose output is covered by the existing template tests

## Applicable Learnings

- Compose `dns:` on a user-defined network sets the embedded resolver's upstream and takes only IP addresses, so
  pointing the agent at a sidecar that way needs a fixed address and therefore a declared subnet. Two sandboxes on
  one host would then collide on the subnet. That rules the `dns:` design out for this repo
- The embedded resolver listens on a random high port on `127.0.0.11` and the port-53 NAT rule only redirects to it
  (audit rows A9, A10). Dropping the NAT rules leaves the listener reachable; the firewall must reject the address
- The firewall's `REJECT` shows up as `EPERM` on a UDP send and `EHOSTUNREACH` on a TCP connect. The self-test can
  assert on a fast failure instead of a timeout
- Runtime sync writes the managed compose layers only when they are missing; only `agentbox init` rewrites them. A
  design that needs a compose change does not reach existing projects on `agentbox up`, so an image-only design
  rolls out through `agentbox bump` alone
- Single-file bind mounts pin the inode. `/etc/resolv.conf` is one, so the firewall script must write it in place;
  a write-and-rename would fail with `EBUSY` and a copy would be invisible
- Keep security invariants attached to the construct that enforces them. The allowed-name set lives in the addon
  that answers queries, and the addon is the only thing that ever resolves a name for the agent
- Entrypoint scripts must be idempotent. The firewall script already re-runs safely; the DNS additions must too,
  including after a container restart when Docker has regenerated nothing and `/etc/resolv.conf` still names the
  old proxy address

## Plan

### Files Involved

- `images/proxy/addons/dns_sinkhole.py` (new): the addon
- `images/proxy/addons/enforcer.py`: register the sinkhole in `build_addons()`
- `images/proxy/Dockerfile`: `ENTRYPOINT` gains `--mode regular@8080 --mode dns@5353`
- `images/proxy/tests/test_dns_sinkhole.py` (new): unit tests
- `images/proxy/tests/integration/harness.py` and `integration/test_dns_sinkhole.py` (new): spawn `mitmdump` in
  DNS mode and query it over UDP and TCP with hand-packed messages
- `images/base/init-firewall.sh`: address discovery, rules, `resolv.conf`, self-tests
- `images/base/entrypoint.sh`: the failure banner names the likely cause when the DNS self-test is what failed
- `scripts/dns-egress-audit/probe.bash`, `expected/*.tsv`, and the milestone's `bypass-matrix.md`: sinkhole
  control rows S1 through S3, and the after-m18.2 values already changed during planning
- `CHANGELOG.md`: an `[Unreleased]` entry that says rebuilt images are required
- `docs/plan/milestones/m18-dns-egress-controls/milestone.md`: record the design choice under `m18.2`

No change under `internal/` or `internal/embeddata/templates/`. The checked-in `.agent-sandbox/` tree changes only
through the normal image bump.

### Approach

**Design choice.** Three shapes were on the table after the audit.

1. Compose `dns:` pointed at a sidecar. Needs a fixed address for the sidecar, hence a declared subnet, hence
   collisions between projects on one host. Also keeps the `127.0.0.11` listener reachable on its real port.
2. A resolver sidecar reached through a DNAT installed at firewall init. Works, but a new service touches
   `depends_on`, healthchecks, both template layers, the checked-in runtime tree, and every command that reasons
   about services. That is the blast radius the milestone warned about.
3. A DNS listener inside the existing proxy container, on an unprivileged port, reached through a port rewrite
   installed at firewall init. No new service, no compose change, and the proxy already has the process, the
   logger, the tests, and the image pipeline.

This task takes option 3. A variant that binds port 53 directly by setting `net.ipv4.ip_unprivileged_port_start=0`
on the proxy service was rejected only because it needs a managed-layer change, and those reach existing projects
only through a fresh `agentbox init`. The port rewrite costs two `nat` rules and nothing else.

**Spike results.** mitmproxy 11.0.2, which the proxy image builds on, supports `--mode dns@PORT` alongside
`regular@8080` and listens on UDP and TCP. Its built-in `DnsResolver` addon runs before script addons and would
resolve every query upstream before ours could refuse it, so the addon removes it in `load()` through
`ctx.master.addons`; the spike confirmed the removal and that afterwards a query the addon leaves unanswered gets
`SERVFAIL` from the layer itself, because DNS mode has no upstream server. That is the fail-closed property. An
allowed name answered through `getaddrinfo` in 6 ms; unknown names got `NXDOMAIN` in the same time over both
transports; a 253-byte name and TXT and AAAA queries behaved as designed.

**Proxy side.** `dns_sinkhole.py` defines `DnsSinkhole`. On `load` it removes the built-in resolver and reads
`AGENTBOX_DNS_ALLOW`, a comma-separated list of exact lowercase names, defaulting to `proxy`. On `dns_request` it
takes the single question and decides: opcode other than `QUERY` or class other than `IN` gets `NOTIMP`; a name
outside the set gets `NXDOMAIN`; an allowed name with type `A` or `AAAA` is resolved with `getaddrinfo` on the
event loop's executor and answered with a 30 second TTL, or with an empty `NOERROR` if that family has no address;
an allowed name with any other type gets an empty `NOERROR`. Every refusal is logged as a JSON event of type `dns`
with the name, type, client address, and action; answers are logged only at verbose level, since the agent's
tooling resolves `proxy` constantly. `enforcer.py` appends the addon to `build_addons()` so one `-s` flag loads
both, and the `Dockerfile` adds the two `--mode` flags. The healthcheck stays on 8080; a DNS listener that failed to
bind would make `mitmdump` exit, which the healthcheck already catches.

**Agent side.** `init-firewall.sh` gains a first step before the flush: resolve `proxy` to an address. On a fresh
network namespace Docker's NAT rules are present and `/etc/resolv.conf` names `127.0.0.11`, so `getent` works as it
does today. After a container restart Docker leaves a modified `resolv.conf` alone, so the script tries the current
nameserver first, and if that fails it writes `nameserver 127.0.0.11` in place and retries while the Docker rules
still exist. Failure to resolve `proxy` at all aborts with a message that says so. Then the flush, without restoring
the Docker DNS rules, and this `OUTPUT` chain in order: reject everything to `127.0.0.11`; accept `lo`; accept UDP
and TCP 5353 to the proxy address; reject UDP and TCP 53 and TCP 853 to anywhere; accept the host network; accept
established; the existing final reject. In the `nat` table, DNAT UDP and TCP 53 to the proxy address onto port
5353. Then write `/etc/resolv.conf` in place with `nameserver <proxy address>` and Docker's `options` line.

The self-tests keep the proxy-reachable loop and change the negative connect test from `https://example.com`, which
can no longer resolve, to an IP literal, so it still proves the firewall rather than the resolver. Two DNS checks
follow: `getent hosts proxy` must return the proxy address, and `getent hosts <random>.example.com` must fail
within two seconds. `entrypoint.sh` prints which self-test failed, and for the DNS pair says the likely cause is a
proxy image without the sinkhole and to run `agentbox bump`.

If the proxy container is recreated with a new address while the agent keeps running, `resolv.conf` and the DNAT
go stale and every lookup fails. Compose normally recreates the agent alongside the proxy. For the case where it
does not, re-running `sudo /usr/local/bin/init-firewall.sh` repairs it, and `m18.5` documents that.

**Audit.** Three control rows join `probe.bash`: S1 sends a random label to `proxy:53` over UDP and expects
`nxdomain` after the rewrite, S2 does the same to `proxy:5353`, and S3 queries `proxy` A at `proxy:53` and expects
`answered`. They are recorded but not compared in the baseline file. The after-m18.2 expectations were already
rewritten during planning: A3 through A7, A9, A10, and B1 through B4 read `rejected`, A1 and A2 `not-found`, A8
`answered`, H1 `not-seen`.

**Tests.** Unit tests build `dns.Message` objects and drive `dns_request` directly: allowed and refused names, each
type, case and trailing-dot handling, the env parsing, and the built-in resolver removal against a fake master. The
integration test spawns `mitmdump --mode dns@<port>` with the enforcer script and `AGENTBOX_DNS_ALLOW=localhost`,
since `proxy` does not resolve on a developer machine, and sends hand-packed queries over UDP and TCP. The harness
gets a `modes` parameter for that. The Go suite is untouched and stays green because nothing under `internal/`
changes. The firewall has no unit harness; its gate is the audit runner at `--stage after-m18.2` in both modes.

**Rollout.** Both images change. A new agent image against an old proxy image fails the DNS self-test and refuses to
start, with the banner naming the cause. An old agent image against a new proxy image keeps today's behaviour, since
nothing points it at the sinkhole. `agentbox bump` moves both pins together. The changelog entry says so.

### Implementation Steps

- [ ] Write `dns_sinkhole.py` and its unit tests; run the proxy suite
- [ ] Register the addon in `enforcer.py`, add the DNS mode to the `Dockerfile`, extend the harness, and add the
      integration test
- [ ] Rewrite `init-firewall.sh`: address discovery with the restart fallback, rule set, DNAT, `resolv.conf`,
      self-tests with the IP-literal negative test and the DNS pair
- [ ] Update the `entrypoint.sh` banner
- [ ] Add S1 through S3 to `probe.bash`, the expected files, and the matrix
- [ ] Write the changelog entry and record the design choice in the milestone plan
- [ ] Maintainer rebuilds with `make setup` and `./images/build.sh proxy`, runs `agentbox up`, and runs the audit
      at `--stage after-m18.2`; iterate on failures from inside the rebuilt sandbox
- [ ] Maintainer repeats the audit with `--container` against the devcontainer
- [ ] Verify each acceptance criterion, capture learnings, and note follow-ups for `m18.3` and `m18.5`

### Open Questions

- Confirm the design: sinkhole inside the proxy on 5353 with the agent-side port rewrite, chosen over binding 53
  through a sysctl because the latter needs a managed-layer change that only `agentbox init` propagates
- `AGENTBOX_DNS_ALLOW` as the override for users who add sidecars the agent must reach by name, exact names only,
  default `proxy`. Say if the name or the exact-only rule is wrong
- The negative connect self-test moves to a public IP literal, `https://1.1.1.1`. The alternative is to keep a
  hostname and accept that the test then proves the resolver rather than the firewall
- The stale-address case after a proxy recreation is handled by documentation and a re-run of the firewall
  script, not by code. Object if that should be automated in this task
- Execution split: code and both test suites run from this sandbox; the image rebuilds, `agentbox up`, and both
  audit runs need the Mac. The user override already selects `agent-sandbox-proxy:local` and the dev agent image,
  so the rebuild is `make setup`, which rebuilds the base layer the firewall script lives in, plus
  `./images/build.sh proxy`. Confirm that is still the flow

## Outcome

### Acceptance Verification

- [ ] From the agent container, a lookup of a random label under a domain we control returns `NXDOMAIN` and no
      query reaches that domain's nameserver
- [ ] `curl -x http://proxy:8080 https://github.com` still succeeds, and an unlisted host still returns the proxy 403
- [ ] A direct query to a public resolver and a direct query to the bridge gateway both fail
- [ ] The firewall self-test fails the container start if either DNS assertion does not hold
- [ ] Both CLI mode and devcontainer mode pass the same assertions
- [ ] `go test ./...` and the proxy suite pass, and generated compose output is covered by the existing template tests

### Learnings

To be filled at completion.

### Follow-up Items

To be filled at completion.
