# Milestone: m18 - DNS Egress Controls

## Goal

Close the last undeclared outbound channel in the sandbox. Today every TCP connection must go through the proxy, but
name resolution is unrestricted: the agent container resolves arbitrary names through Docker's embedded resolver at
`127.0.0.11`, which forwards recursively to the host's resolver and out to the internet. An attacker-controlled
authoritative nameserver sees every query name, so a query for `<base32-of-secret>.exfil.example` leaks data without
the agent ever opening a socket the firewall would block. TXT answers make it bidirectional.

After this milestone, a name the policy does not need does not resolve, and an allowed name cannot be pointed at an
address the proxy should refuse.

## Scope

Included:

- A sinkhole resolver for the agent container that answers compose service names and returns `NXDOMAIN` for
  everything else
- Firewall changes so port 53 reaches only that resolver, replacing today's restoration of Docker's DNS NAT rules
- IPv6 egress parity, so the sinkhole cannot be stepped around over a second address family
- A proxy-side address guard that re-checks the resolved address of an allowed host and refuses private, loopback,
  link-local, and cloud-metadata ranges
- The same treatment in devcontainer mode. Its templates set `overrideCommand: false`, so the image entrypoint and
  `init-firewall.sh` run there too, and the acceptance tests must prove that stays true
- A documented and reproducible bypass matrix, plus regression tests at the level each control can actually be tested
- User-facing docs and a note in the image-baked `operating-in-agent-sandbox` skill

Excluded:

- A policy surface for DNS. Resolvable names stay derived from the compose stack, not authored. If a user needs a name
  resolved, the proxy resolves it on their behalf; the agent never needs to
- DNS-over-HTTPS to an already-allowed host. A host on the allowlist that also serves DoH is a smaller case of the
  allowed-host exfiltration problem this milestone does not try to solve. Recorded as a risk
- Response-content inspection or any attempt to detect encoded data in query names. This milestone removes the
  channel rather than policing it
- Egress controls for the proxy container itself, which must resolve allowed hosts
- Blocking the Docker bridge gateway wholesale. Rule 5 of `init-firewall.sh` allows the host network in both
  directions because that is how the proxy sidecar is reached; narrowing it is a separate change
- SNI and Host alignment checks, redirect re-authorization, and the other L7 defenses listed in the alternatives
  research. Those belong with a request-inspection milestone

## Applicable Learnings

- "iptables rules must preserve Docker's internal DNS resolution (127.0.0.11 NAT rules) or container DNS breaks" is
  the first line of `learnings.md`. The `m18.1` audit showed why: on a user-defined network the `127.0.0.11` stub is
  the only source of compose service names. Whatever `m18.2` picks must keep `proxy` resolving for `HTTPS_PROXY`
- Environment-variable proxy configuration is advisory; network-level enforcement is what counts. The same reasoning
  applies here. A resolver the agent is merely pointed at is not a control unless the firewall also stops it from
  reaching any other resolver
- VS Code devcontainers replace the container command by default. The devcontainer templates set
  `overrideCommand: false` so the image entrypoint runs in both modes; a firewall change that lives only in the
  entrypoint depends on that setting staying in place
- Defense in depth works when layers serve different purposes. The firewall restricts where port 53 may go; the
  resolver decides which names exist; the proxy decides which addresses are acceptable. Three layers, three jobs
- Integration coverage catches wiring that unit tests miss. A resolver that unit-tests correctly can still leave the
  stack broken if `depends_on` ordering lets the agent start before it is listening
- The proxy container runs as a non-root user with `cap_drop: ALL`, so binding port 53 needs either
  `CAP_NET_BIND_SERVICE` or an unprivileged-port sysctl. This shapes the sidecar-versus-in-proxy decision in `m18.2`
- Keep security invariants attached to the construct that enforces them. The address guard belongs where the proxy
  opens the upstream connection, not in documentation telling users to avoid rebinding

## Tasks

### m18.1-egress-channel-audit

**Summary:** Prove which outbound channels exist today and turn the result into a reusable bypass matrix.

**Scope:**
- Run each candidate channel from inside a current sandbox and record whether it escapes: `getaddrinfo` through
  `127.0.0.11`, direct queries to the Docker bridge gateway, direct queries to a public resolver, TCP/53, DNS-over-TLS
  on 853, DNS-over-HTTPS to an allowed host, and IPv6 equivalents of each
- Confirm the exfiltration path end to end against a nameserver under our control, so the finding is a demonstration
  and not an inference
- Record whether Docker's embedded resolver is reachable over TCP as well as UDP, and what it does with `TXT`, `NULL`,
  and long label chains
- Check whether the Colima VM's bridge gateway runs a resolver the agent can reach directly, since the host network is
  allowed in both directions
- Determine whether the compose network has IPv6 enabled by default on the supported platforms, and what
  `init-firewall.sh` leaves unprotected when it does
- Package the probes as a script that can be re-run after each subsequent task

**Acceptance Criteria:**
- A checked-in matrix lists every probe, the observed result before any change, and the expected result after
- The demonstration of the query-name channel is reproducible by a second person from the write-up
- Every later task in this milestone has at least one probe that must flip from escape to blocked
- No probe depends on a nameserver or domain that outlives the audit

### m18.2-dns-sinkhole

**Summary:** Give the agent container a resolver that answers compose service names and nothing else, and point the
firewall at it.

**Scope:**
- Decide between a dedicated resolver sidecar and adding a resolver to the existing proxy container, and record the
  decision. The proxy container currently runs as a non-root user with all capabilities dropped, so binding port 53
  there requires a capability or a sysctl; a sidecar keeps that boundary intact at the cost of one more service
- Choose how the agent reaches the resolver, using the `m18.1` audit (`bypass-matrix.md`, findings 9 and 10). On a
  user-defined network Docker keeps the stub at `127.0.0.11` and treats compose `dns:` as the embedded resolver's
  upstream list, dialed from the container's own namespace. Two coherent designs follow. With `dns:`, the embedded
  resolver keeps answering service names from IPAM and forwards everything else to the sinkhole, which answers
  `NXDOMAIN`; the `127.0.0.11` NAT rules stay restored, and the sinkhole needs a fixed address because `dns:` takes
  IP addresses, which means a declared subnet. With a DNAT at firewall init, `init-firewall.sh` resolves the
  sinkhole's current address through the embedded resolver and replaces Docker's `127.0.0.11` DNAT with one to the
  sinkhole; the sinkhole answers service names by forwarding to its own embedded resolver on the same network and
  `NXDOMAIN` for everything else. Either way, serve only the names the stack needs and never a static hosts file
  keyed on container IPs, which change between runs. Record the choice for the decision record `m18.5` writes
- Return `NXDOMAIN` promptly rather than dropping, so a blocked lookup fails fast instead of hanging on a resolver
  timeout the way a silent drop would
- Wire the chosen design into the managed base layer, which both CLI mode and the devcontainer templates consume
- Add the resolver to the agent's `depends_on` with a health condition, so the agent cannot start before name
  resolution exists
- Change `init-firewall.sh`: allow UDP and TCP port 53 only to the resolver's address, ahead of the host-network
  rule, so a peer container on the compose network and the bridge gateway stop being reachable on port 53 (audit
  rows B1 through B4). Keep the existing positive and negative self-tests and add a DNS pair to them, one name that
  must resolve and one that must not; audit finding 5 gives the errno signatures to assert on
- Leave the proxy container's own resolution untouched
- Regenerate this repo's checked-in `.agent-sandbox/` runtime so local development exercises the new stack
- Decided 2026-09-12: the sinkhole is a mitmproxy DNS-mode addon inside the proxy container on port 5353, reached
  through a port rewrite in the agent's firewall, with Docker's resolver rejected outright. No compose change, so
  `agentbox bump` alone rolls it out and the runtime tree needs no regeneration. The comparison with the `dns:`
  upstream, sidecar, and sysctl variants and the spike results are in `tasks/m18.2-dns-sinkhole/task.md`

**Acceptance Criteria:**
- From the agent container, a lookup of a random label under a domain we control returns `NXDOMAIN` and no query
  reaches that domain's nameserver
- `curl -x http://proxy:8080 https://github.com` still succeeds, and an unlisted host still returns the proxy 403
- A direct query to a public resolver and a direct query to the bridge gateway both fail
- The firewall self-test fails the container start if either DNS assertion does not hold
- Both CLI mode and devcontainer mode pass the same assertions
- `go test ./...` and the proxy suite pass, and generated compose output is covered by the existing template tests

### m18.3-ipv6-egress-parity

**Summary:** Apply the same default-deny posture to IPv6 so the sinkhole cannot be stepped around over a second
address family.

**Scope:**
- Extend `init-firewall.sh` to program `ip6tables` alongside `iptables`: default-deny policies, loopback, the host
  network, established and related, and the same port 53 exception to the resolver
- Handle the case where the kernel or image lacks `ip6tables` support, failing closed with a clear message rather
  than silently leaving IPv6 unfiltered
- Decide whether to disable IPv6 on the compose network instead, and record why the chosen option was picked. If
  IPv6 is disabled rather than filtered, the firewall should assert that it is actually off rather than assume it
- Add the IPv6 probes from `m18.1` to the firewall self-test
- The audit found `ip6tables` present in the image with ACCEPT policies and no rules, and `EnableIPv6=false` on the
  compose network. Enable IPv6 on the network for the `after-m18.3` audit run, or the E rows cannot flip
- Decided 2026-09-17: deny all IPv6 except loopback (`::1` only) and established traffic, with no host-network or
  port 53 exception, because the agent reaches the proxy and the sinkhole over IPv4 by construction. The rules go
  in whether or not the network has IPv6; the firewall fails closed only when IPv6 is present and `ip6tables` is
  unavailable. This repo's dev sandbox kept IPv6 enabled so the path was exercised daily, until `m18.6` moved that
  coverage into CI and turned it off on 2026-10-01. The alternatives and the reasoning are in
  `tasks/m18.3-ipv6-egress-parity/task.md`

**Acceptance Criteria:**
- With IPv6 available on the network, every IPv6 probe from the audit is blocked
- With IPv6 unavailable, container start still succeeds and the self-test says so explicitly
- No IPv4 behavior changes

**Dependencies:** `m18.2`, which defines the resolver address the exception points at.

### m18.4-proxy-address-guard

**Summary:** Refuse allowed hosts that resolve to addresses the sandbox should never reach.

**Scope:**
- At the point where the proxy opens an upstream connection, check the resolved address against a deny set: loopback,
  private ranges, link-local including `169.254.169.254`, unique-local and link-local IPv6, and the Docker bridge
  network the sandbox itself runs on
- Apply the check to both the CONNECT fast path and the request path, so a host-only rule is covered as well as a
  request-aware one
- Emit a distinct structured decision event so a refusal is distinguishable from a policy miss in the logs, and
  return a proxy error body that names the reason
- Decide whether to pin the connection to the checked answer or to re-check after connect, and record the residual
  time-of-check risk either way
- Add an escape hatch only if the existing tests need one for loopback rebinding in the integration harness, and keep
  it out of the authored policy surface

**Acceptance Criteria:**
- A host on the allowlist whose DNS answer is a private or link-local address is refused, with a log event naming
  the address class
- The existing integration harness, which rebinds rendered hosts onto loopback, still passes, either through the
  documented escape hatch or by an explicit test-only configuration
- No change in behavior for hosts that resolve to ordinary public addresses
- Proxy unit and integration tests cover each refused address class

- Decided 2026-09-27: the guard is a separate addon hooking `server_connect`, the one point every upstream
  connection passes through. A wrapper on the running loop's `getaddrinfo` checks the dial's own lookup and refuses
  before any socket opens if any answer is denied, so the check and the dial are one lookup; rewriting
  `server.address` was spiked and breaks tunnelled requests, and staging checked answers was built first and
  replaced after the #204 review found unchecked fallbacks. Invariant tests fail on any mitmproxy or Python bump
  that breaks the wrapper.
  Refusals are 403, IP-literal hosts are exempt, and there is no operator hatch yet. Reasoning in
  `tasks/m18.4-proxy-address-guard/task.md`

**Dependencies:** None on the other tasks; can run in parallel with `m18.2` and `m18.3`.

### m18.5-docs-tests-and-agent-guidance

**Summary:** Document the new boundary, wire the probes into the test suites, and tell agents what changed.

**Scope:**
- Update `docs/policy/schema.md` to state plainly that DNS is not policy-controlled and why, so nobody goes looking
  for a `dns:` key
- Add a troubleshooting entry for the failure this will actually produce: a tool that resolves names itself now gets
  `NXDOMAIN` instead of a connection error, and the fix is to route it through the proxy
- Document the threat in `docs/` in one short section: what DNS exfiltration is, what the sandbox now does about it,
  and the residual cases that remain open
- Add a note to the image-baked `operating-in-agent-sandbox` skill so an agent that hits `NXDOMAIN` understands the
  cause instead of retrying or concluding the network is broken
- Fold the `m18.1` probes into whatever automated coverage they fit: proxy tests for the address guard, the firewall
  self-test for the in-container assertions, and a documented manual matrix for anything needing a real nameserver
- Record a decision document for the sinkhole approach, following the numbering in `docs/plan/decisions/`

**Acceptance Criteria:**
- A user who hits the new failure mode can diagnose it from the troubleshooting entry alone
- The decision record states the alternatives considered and why a policy-driven resolver was rejected
- Every control in this milestone has either automated coverage or a documented manual procedure, and the split is
  explicit
- No doc still describes container DNS as unrestricted

**Dependencies:** `m18.2`, `m18.3`, `m18.4`.

### m18.6-firewall-ci-tests

**Summary:** Follow-up opened 2026-09-28. Run the agent firewall and the DNS sinkhole end to end in CI with IPv6 on and
off, so this repo's dev sandbox no longer has to keep IPv6 enabled to exercise the IPv6 path. Plan in
`tasks/m18.6-firewall-ci-tests/task.md`.

**Dependencies:** `m18.2` and `m18.3`. Lands in PR #204 with the rest of the milestone.

## Execution Order

1. `m18.1` first. It is cheap, it establishes the baseline, and every later acceptance criterion refers to its matrix.
2. `m18.2` is the core change and the one most likely to surface surprises in compose wiring and devcontainer mode.
3. `m18.3` follows `m18.2` because it needs the resolver's address. `m18.4` is independent and can run in parallel
   with either.
4. `m18.5` last, once the behavior is settled.

Decision point after `m18.1`, resolved 2026-09-12: the audit found no resolver on the bridge gateway. The VM's
`dnsmasq` listens on `192.168.5.1` and loopback only, which the container already cannot reach, so rule 5 stays as
it is and `m18.2` restricts port 53 within the host network to the resolver's address. See `bypass-matrix.md` rows
B1, B2, and H2.

## Risks

- Breaking name resolution breaks everything. Any tool that resolves a hostname directly rather than handing it to the
  proxy stops working. The audit in `m18.1` should list which bundled tools do that before `m18.2` lands, and the
  rollout should be verified against each supported agent image, not just one
- The devcontainer path has historically diverged from the compose path. Today both modes consume the same managed
  base layer and run the same entrypoint, but only the acceptance tests running in both modes prove that. A control
  that quietly applies to one mode leaves IDE users unprotected and, worse, looks fixed
- Adding a service to the compose stack touches `depends_on`, healthchecks, generated templates, the checked-in
  runtime tree, and every `agentbox` command that reasons about services. The blast radius is wider than the size of
  the change suggests
- An allowed host that also serves DNS-over-HTTPS reopens a query channel at a smaller scale. This milestone does not
  close it, and the docs should say so rather than overclaim
- The address guard has an unavoidable time-of-check-to-time-of-use gap unless the connection is pinned to the
  checked answer. Whichever option is chosen, the residual risk belongs in the decision record
- Chasing DNS can look like security theater next to the larger allowed-host channel. The honest framing is that this
  closes a channel that exists regardless of policy, at low cost, and it is table stakes in comparable tools; it does
  not reduce what an allowed host can carry
- `NXDOMAIN` for an unexpected name is a new, unfamiliar failure mode. Without the skill note and troubleshooting
  entry, agents will burn turns misdiagnosing it

## Definition of Done

- A lookup from the agent container for any name the stack does not need returns `NXDOMAIN`, and no query for it
  leaves the host
- Port 53 from the agent container reaches only the sandbox resolver, over IPv4 and IPv6, in both CLI and devcontainer
  mode
- The firewall self-test asserts both the positive and negative DNS cases at container start and fails the start if
  either does not hold
- An allowed host that resolves to a private, loopback, link-local, or metadata address is refused by the proxy with a
  distinct log event
- The bypass matrix from `m18.1` re-runs clean, and each entry is covered by an automated test or a documented manual
  procedure
- Docs, troubleshooting, the agent skill, and a decision record are updated, including the residual gaps

## Changes

### 2026-10-01: m18.6 closed

The firewall, the DNS sinkhole, and the address guard now run end to end in CI with IPv6 on and off, on every change
to the images or the audit. The first CI runs found that Docker's upstream on GitHub's runners is systemd-resolved's
loopback, which the audit's C1 and C2 cannot test; they now report `not-applicable` there. A deliberate-failure run
added a fifth startup check, for Docker's resolver. This repo's dev sandbox runs with IPv6 off from here on.

### 2026-09-28: m18.6 opened as a follow-up

Keeping IPv6 on in the dev sandbox was the only recurring exercise of the IPv6-present firewall path. `m18.6` moves
that into CI, covering both IPv6 paths on every relevant PR, and then turns IPv6 off in the dev sandbox so it matches
what users run.

### 2026-09-28: m18.5 and the milestone closed

Every item of the definition of done holds. A name the stack does not need gets `NXDOMAIN` and no query leaves the
host, shown by a VM capture with a positive control; port 53 reaches only the sinkhole over IPv4 and IPv6 in both
modes; the self-test fails a start in both DNS directions, the failing one observed against a pre-sinkhole proxy
image; the address guard refuses internal answers with its own event; the bypass matrix re-runs clean and its coverage
table gives every control an automated test or a manual procedure; and the docs, troubleshooting, agent skill, and
decisions 009 and 010 are written, residual gaps included. Out-of-scope findings went to `docs/plan/cleanup-tasks.md`.

### 2026-09-28: m18.4 guard reworked after review

The #204 review found that staging checked answers left the dial an unchecked fallback whenever the staged entry was
missing, failed, expired during mitmproxy's connection-semaphore wait, or was overwritten by another connection. The
wrapper now checks the dial's own lookup, which removes the fallback. The same review tightened the IPv6 fail-closed
check to any IPv6 address and made the audit exit 2 when it skipped expected rows.

### 2026-09-27: m18.4 closed

All four acceptance criteria verified in both modes. An allowed name resolving to a denied address gets a 403 naming
the guard and the address class, the dial is pinned to the checked answers, and nothing changes for public
addresses or IP-literal hosts. The audit's D1 row moved to a DoH host the probe setup never allows, after the first
`--policy-probes` run showed D1 and D2 had conflicted since `m18.1`. Only `m18.5` remains.

### 2026-09-27: m18.4 design chosen and implemented from the sandbox

Check and pin in `server_connect`, with the pin done by staging checked answers for the loop's `getaddrinfo`, a
monkeypatch accepted on the condition that tests fail when its invariants break. The milestone's scope said to add
an escape hatch only if the tests needed one; they need none because IP-literal hosts are exempt, and the
maintainer chose to ship without an operator hatch until a user reports an internal host. Refusals answer 403
rather than mitmproxy's 502, so an agent reads them as a proxy refusal and does not retry.

### 2026-09-27: m18.3 closed

All three acceptance criteria verified in both modes. With IPv6 enabled on the compose network, every IPv6 probe
is rejected, and with it off the self-test names the state; the IPv4 rows are unchanged. The audit's H1 row gained
a positive control after two runs captured no DNS at all. This repo's dev sandbox now runs with IPv6 on. `m18.4`
and `m18.5` remain.

### 2026-09-17: m18.3 design chosen

IPv6 is denied outright except loopback and return traffic, rather than mirrored from the IPv4 rule set. The
mirrored host-network and port 53 exceptions would have had no consumer, since the agent reaches the proxy over
IPv4, and would have needed ICMPv6 neighbour-discovery rules and a DNAT on the proxy's IPv6 address that only an
IPv6-enabled run could test. Disabling IPv6 on the network was rejected because it needs a managed-layer change and
leaves a user who enables IPv6 unfiltered. Loopback means `::1` alone, so a resolver address Docker might add to
`lo` is denied without being known. This repo's dev sandbox enables IPv6 on its compose network from here on.

### 2026-09-17: m18.2 closed

Both audit runs are clean in CLI and devcontainer mode and five of six acceptance criteria are verified with
evidence. The failing direction of the DNS self-test, a start against a pre-sinkhole proxy image, and the dynamic
check of the tool inventory's "verify" entries are deferred by the maintainer; both are listed under the task's
follow-ups and the matrix's pending section. Along the way the proxy image, the dev venv, and CI were pinned to
mitmproxy 12.2.3 from one `ARG` line, and `mitmdump` runs through a launcher that skips interpreter teardown because
11.0.2 crashed on shutdown in DNS mode. `m18.3` planning opened the same day.

### 2026-09-12: m18.2 design chosen

The sinkhole lives in the proxy container as a mitmproxy DNS-mode addon on an unprivileged port; the agent's
firewall rewrites port 53 to it. Chosen over the `dns:` upstream (fixed address, subnet collisions), a sidecar
(blast radius), and a sysctl to bind 53 (needs a managed-layer change only `agentbox init` propagates). The audit
gained rows A9 and A10 for the embedded resolver's real listening ports.

### 2026-09-12: m18.1 findings folded in

The audit resolved the rule 5 decision point and corrected the `m18.2` scope: compose `dns:` sets the embedded
resolver's upstream rather than replacing the stub, so the NAT restore stays with that design and the sinkhole
needs a fixed address; the DNAT-at-init alternative is recorded alongside it. `m18.3` gained the note that IPv6
must be enabled on the network for its audit run.

### 2026-09-12: Renumbered from m21 to m18

Inserted ahead of the planned credential and monitoring milestones, none of which have shipped. Provider API-key
injection moved to `m19`, CLI monitoring to `m20`, and the host credential service to `m21`.

### 2026-09-12: Created

Opened after the DNS channel came up while reviewing `docs/plan/research/alternatives.md`. The research pass found
that Coder Boundary, httpjail, airut, iron-proxy, Docker Sandboxes, and OpenSandbox all sinkhole or intercept DNS,
and that AWS shipped a sandbox network mode with this same hole and had to clarify it after researchers used it. The
current `init-firewall.sh` deliberately restores Docker's DNS NAT rules, so the channel is open here by design rather
than by oversight.
