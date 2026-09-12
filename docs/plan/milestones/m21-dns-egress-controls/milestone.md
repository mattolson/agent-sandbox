# Milestone: m21 - DNS Egress Controls

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
- The same treatment in devcontainer mode, which initializes the firewall through `postStartCommand` rather than the
  entrypoint
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
  the first line of `learnings.md`, and it is exactly what this milestone reverses. The replacement has to resolve
  compose service names itself, because the agent still needs `proxy` to resolve for `HTTPS_PROXY` to work
- Environment-variable proxy configuration is advisory; network-level enforcement is what counts. The same reasoning
  applies here. A resolver the agent is merely pointed at is not a control unless the firewall also stops it from
  reaching any other resolver
- VS Code devcontainers bypass Docker `ENTRYPOINT`, so anything added to firewall init needs the `postStartCommand`
  path checked too
- Defense in depth works when layers serve different purposes. The firewall restricts where port 53 may go; the
  resolver decides which names exist; the proxy decides which addresses are acceptable. Three layers, three jobs
- Integration coverage catches wiring that unit tests miss. A resolver that unit-tests correctly can still leave the
  stack broken if `depends_on` ordering lets the agent start before it is listening
- The proxy container runs as a non-root user with `cap_drop: ALL`, so binding port 53 needs either
  `CAP_NET_BIND_SERVICE` or an unprivileged-port sysctl. This shapes the sidecar-versus-in-proxy decision in `m21.2`
- Keep security invariants attached to the construct that enforces them. The address guard belongs where the proxy
  opens the upstream connection, not in documentation telling users to avoid rebinding

## Tasks

### m21.1-egress-channel-audit

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

### m21.2-dns-sinkhole

**Summary:** Give the agent container a resolver that answers compose service names and nothing else, and point the
firewall at it.

**Scope:**
- Decide between a dedicated resolver sidecar and adding a resolver to the existing proxy container, and record the
  decision. The proxy container currently runs as a non-root user with all capabilities dropped, so binding port 53
  there requires a capability or a sysctl; a sidecar keeps that boundary intact at the cost of one more service
- Serve only the names the stack needs. Forward the compose service names to the container's own embedded resolver so
  service discovery keeps working through Docker's IPAM, and answer `NXDOMAIN` for every other name. Do not use a
  static hosts file keyed on container IPs, which change between runs
- Return `NXDOMAIN` promptly rather than dropping, so a blocked lookup fails fast instead of hanging on a resolver
  timeout the way a silent drop would
- Point the agent container at the resolver with compose `dns:`, in the managed base layer and in the devcontainer
  mode layer
- Add the resolver to the agent's `depends_on` with a health condition, so the agent cannot start before name
  resolution exists
- Change `init-firewall.sh`: stop extracting and restoring the `127.0.0.11` NAT rules, and allow UDP and TCP port 53
  only to the resolver's address. Keep the existing positive and negative self-tests and add a DNS pair to them, one
  name that must resolve and one that must not
- Leave the proxy container's own resolution untouched
- Regenerate this repo's checked-in `.agent-sandbox/` runtime so local development exercises the new stack

**Acceptance Criteria:**
- From the agent container, a lookup of a random label under a domain we control returns `NXDOMAIN` and no query
  reaches that domain's nameserver
- `curl -x http://proxy:8080 https://github.com` still succeeds, and an unlisted host still returns the proxy 403
- A direct query to a public resolver and a direct query to the bridge gateway both fail
- The firewall self-test fails the container start if either DNS assertion does not hold
- Both CLI mode and devcontainer mode pass the same assertions
- `go test ./...` and the proxy suite pass, and generated compose output is covered by the existing template tests

### m21.3-ipv6-egress-parity

**Summary:** Apply the same default-deny posture to IPv6 so the sinkhole cannot be stepped around over a second
address family.

**Scope:**
- Extend `init-firewall.sh` to program `ip6tables` alongside `iptables`: default-deny policies, loopback, the host
  network, established and related, and the same port 53 exception to the resolver
- Handle the case where the kernel or image lacks `ip6tables` support, failing closed with a clear message rather
  than silently leaving IPv6 unfiltered
- Decide whether to disable IPv6 on the compose network instead, and record why the chosen option was picked. If
  IPv6 is disabled rather than filtered, the firewall should assert that it is actually off rather than assume it
- Add the IPv6 probes from `m21.1` to the firewall self-test

**Acceptance Criteria:**
- With IPv6 available on the network, every IPv6 probe from the audit is blocked
- With IPv6 unavailable, container start still succeeds and the self-test says so explicitly
- No IPv4 behavior changes

**Dependencies:** `m21.2`, which defines the resolver address the exception points at.

### m21.4-proxy-address-guard

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

**Dependencies:** None on the other tasks; can run in parallel with `m21.2` and `m21.3`.

### m21.5-docs-tests-and-agent-guidance

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
- Fold the `m21.1` probes into whatever automated coverage they fit: proxy tests for the address guard, the firewall
  self-test for the in-container assertions, and a documented manual matrix for anything needing a real nameserver
- Record a decision document for the sinkhole approach, following the numbering in `docs/plan/decisions/`

**Acceptance Criteria:**
- A user who hits the new failure mode can diagnose it from the troubleshooting entry alone
- The decision record states the alternatives considered and why a policy-driven resolver was rejected
- Every control in this milestone has either automated coverage or a documented manual procedure, and the split is
  explicit
- No doc still describes container DNS as unrestricted

**Dependencies:** `m21.2`, `m21.3`, `m21.4`.

## Execution Order

1. `m21.1` first. It is cheap, it establishes the baseline, and every later acceptance criterion refers to its matrix.
2. `m21.2` is the core change and the one most likely to surface surprises in compose wiring and devcontainer mode.
3. `m21.3` follows `m21.2` because it needs the resolver's address. `m21.4` is independent and can run in parallel
   with either.
4. `m21.5` last, once the behavior is settled.

Decision point after `m21.1`: if the audit shows the bridge gateway exposes a resolver the agent can reach directly,
the firewall change in `m21.2` grows to narrow rule 5 rather than just redirect port 53, and that is a larger change
worth re-scoping before starting.

## Risks

- Breaking name resolution breaks everything. Any tool that resolves a hostname directly rather than handing it to the
  proxy stops working. The audit in `m21.1` should list which bundled tools do that before `m21.2` lands, and the
  rollout should be verified against each supported agent image, not just one
- The devcontainer path has historically diverged from the compose path. A change that lands only in the entrypoint
  leaves IDE users unprotected and, worse, looks fixed
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
- The bypass matrix from `m21.1` re-runs clean, and each entry is covered by an automated test or a documented manual
  procedure
- Docs, troubleshooting, the agent skill, and a decision record are updated, including the residual gaps

## Changes

### 2026-09-12: Created

Opened after the DNS channel came up while reviewing `docs/plan/research/alternatives.md`. The research pass found
that Coder Boundary, httpjail, airut, iron-proxy, Docker Sandboxes, and OpenSandbox all sinkhole or intercept DNS,
and that AWS shipped a sandbox network mode with this same hole and had to clarify it after researchers used it. The
current `init-firewall.sh` deliberately restores Docker's DNS NAT rules, so the channel is open here by design rather
than by oversight.

Numbered `m21` because `m18` through `m20` are already assigned. Note that
`docs/plan/research/alternatives.md` proposes a speculative `m21` through `m26` for backend-abstraction work; those
are proposals in a research document, not created milestones, and should shift by one if they are ever opened.
