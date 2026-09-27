# Task: m18.4 - proxy address guard

## Summary

Refuse allowed hosts that resolve to addresses the sandbox should never reach.

## Scope

From the milestone plan, with the adjustments proposed under Approach and listed as open questions:

- At the point where the proxy opens an upstream connection, resolve the host, check every answer against a deny set
  (loopback, private, link-local including `169.254.169.254`, unique-local and link-local IPv6, the sandbox's own
  networks, and the other non-global ranges), and refuse the connection if any answer is denied
- Pin the dial to the checked address so a second resolution cannot hand mitmproxy a different one
- One enforcement point, mitmproxy's `server_connect` hook, which every upstream connection passes through: CONNECT
  tunnels, decrypted requests, and plain HTTP alike. That covers both the CONNECT fast path and the request path the
  milestone names
- Emit a distinct structured event naming the host, the address, and the address class, and put the reason in the
  error body the client receives
- Proposed: hosts written as IP literals are exempt. The guard protects an allowed name from being pointed somewhere
  unexpected; a literal is an explicit address in a policy the agent cannot edit
- Proposed: an operator allow list of CIDRs, `AGENTBOX_ADDRESS_GUARD_ALLOW` on the proxy service, outside the authored
  policy surface. The milestone allowed a hatch only for tests; users who allowlist an internal host need one too
- Update the audit so D3 and D4 can tell a guard refusal from a refused port, and the `after-m18.4` expectations
- Rollout is image-only, proxy image only: `agentbox bump` then `agentbox up`. Changelog entry
- Out of scope: user docs and the decision record, which `m18.5` writes; SNI and Host alignment, redirect
  re-authorization; the DoH residual (D2)

## Acceptance Criteria

- [ ] A host on the allowlist whose DNS answer is a private or link-local address is refused, with a log event naming
      the address class
- [ ] The existing integration harness, which rebinds rendered hosts onto loopback, still passes, either through the
      documented escape hatch or by an explicit test-only configuration
- [ ] No change in behavior for hosts that resolve to ordinary public addresses
- [ ] Proxy unit and integration tests cover each refused address class

## Applicable Learnings

- Keep security invariants attached to the construct that enforces them (milestone). The guard belongs where the
  proxy opens the upstream connection, which in mitmproxy is the `server_connect` hook, not in the policy matcher
  and not in documentation
- Integration coverage catches wiring that unit tests miss (m14). The pinning depends on the order in which
  mitmproxy reads `server.address`; only a test against the real `mitmdump` proves it
- mitmproxy forwards to the host named in the URL it receives, so the integration tests put IP literals in the policy
  rather than rebinding names (m15). The second acceptance criterion's "rebinds rendered hosts onto loopback" is
  `remap_rendered_host`, which rewrites the policy host to `127.0.0.1`; no DNS is involved
- A version that the image, the dev venv, and CI all need belongs on one line (m18.2). mitmproxy is pinned to 12.2.3
  there, which is what makes relying on its hook order acceptable
- An empty capture is not evidence of absence (m18.3). The audit's D3 and D4 already read `http-502` before this
  task, because the proxy dials and the port refuses; a guard that also answers 502 would pass the audit without the
  audit proving anything
- Facts from mitmproxy 12.2.3, read from the installed source:
  - `server_connect` fires in `ConnectionHandler.open_connection` before `asyncio.open_connection(*address)`, and
    setting `data.server.error` there kills the connection before any packet is sent (`proxy/server.py`)
  - `server_connected` cannot abort: its handler ignores `error` and completes the open. So a post-connect check on
    `peername` is not available without reaching into mitmproxy's transports
  - A killed connection reaches the client as a 502. For an eager CONNECT the body is
    `Cannot connect to <host:port>: Connection killed: <error> ...`; for a plain or decrypted request it goes through
    `ResponseProtocolError` with `CONNECT_FAILED`. To confirm in the spike
  - In regular mode `request.host` comes from the request line or Host header, not from `server.address`; only
    transparent mode copies the address into the request (`proxy/layers/http/__init__.py:224`)
  - `server.sni` is set from the hostname when `get_connection` creates the server, before `server_connect`. For the
    eager connection a CONNECT opens, `sni` is still unset at dial time and the TLS layer later fills it from the
    client's SNI or `address[0]` (`addons/tlsconfig.py:291`)
  - Connection reuse compares `address` exactly (`connection_spec_matches`). A connection whose address stayed
    rewritten to an IP would never be reused
  - `connection_strategy` defaults to `eager`: a CONNECT dials upstream before the proxy answers the CONNECT

## Plan

### Files Involved

- `images/proxy/addons/address_guard.py` (new): the classifier, the resolver, and the `AddressGuard` addon
- `images/proxy/addons/enforcer.py`: register the guard in `build_addons()` beside the sinkhole; document the new
  environment variable in the module docstring
- `images/proxy/tests/test_address_guard.py` (new): classifier and hook unit tests with an injected resolver
- `images/proxy/tests/integration/test_address_guard.py` (new) and a test-only addon under
  `images/proxy/tests/integration/` that replaces the guard's resolver, loaded with an extra `-s` by the harness
- `images/proxy/tests/integration/harness.py`: an `extra_addons` parameter for that addon
- `scripts/dns-egress-audit/probe.bash`: D3 and D4 recognise the guard's marker in the response body
- `scripts/dns-egress-audit/expected/after-m18.4.tsv`, `README.md`, and the milestone's `bypass-matrix.md`
- `CHANGELOG.md`: an `[Unreleased]` entry, including what an operator with an internal allowed host must set
- `docs/plan/milestones/m18-dns-egress-controls/milestone.md`: record the design choice under `m18.4`

No change under `internal/`, `images/base/`, or the compose templates. The proxy `Dockerfile` copies `addons/` whole.

### Approach

**Design choice.** Three shapes were on the table.

1. Check, then let mitmproxy dial. Resolve and classify in `server_connect`, refuse on a denied answer, and otherwise
   leave the hostname in place so `asyncio.open_connection` resolves it again. Simple and uses no mitmproxy
   internals, but the second resolution is the rebinding window: a nameserver that answers a public address to the
   check and a private one to the dial, with TTL 0, walks through. The Colima VM's `dnsmasq` honours TTL 0.
2. Check and pin. The same check, then set `server.address` to `(checked_ip, port)` for the dial and restore the
   hostname in `server_connected` and `server_connect_error`. The dial goes to exactly the address that was checked,
   so there is no time-of-check gap. SNI and certificate verification stay on the hostname: `sni` is already set on
   request-path connections, and on the eager CONNECT connection the hostname is back in `address` before TLS
   starts. Reuse keeps working because the address matches again once the connection is open. The cost is a
   dependency on the order in which mitmproxy reads `address`, and the loss of `asyncio`'s fallback to the next
   answer when the first does not connect.
3. A request-phase check in the enforcer's `http_connect` and `requestheaders` hooks, answering 403 through the
   existing block path, plus option 2 underneath for the race. A familiar status code, but two resolutions per
   request, including requests on a connection that is already open and already checked, and two places that must
   agree.

This task proposes option 2, subject to a spike and open question 1.

**Spike first.** Against `mitmdump` 12.2.3 with a throwaway addon: rewrite the address in `server_connect`, restore it
in `server_connected`, and confirm (a) an HTTPS request through a CONNECT tunnel reaches a local TLS upstream with SNI
and certificate verification on the hostname, (b) two requests on one tunnel reuse one upstream connection, (c) a
plain HTTP request is pinned the same way, (d) the refusal body a client receives on each path. If any of these fails,
fall back to option 1 and record the residual.

**Classifier.** A table of `(network, class)` pairs checked in order, first match wins, so the specific name beats the
general one:

| Class | Networks |
|-------|----------|
| `metadata` | `169.254.169.254/32`, `fd00:ec2::254/128` |
| `sandbox_network` | the proxy container's own interface networks, read at load from `/proc/net/route` and `/proc/net/ipv6_route` |
| `loopback` | `127.0.0.0/8`, `::1/128` |
| `private` | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| `unique_local` | `fc00::/7` |
| `link_local` | `169.254.0.0/16`, `fe80::/10` |
| `shared` | `100.64.0.0/10` |
| `unspecified` | `0.0.0.0/8`, `::/128` |
| `multicast` | `224.0.0.0/4`, `ff00::/8` |
| `reserved` | anything else Python's `ipaddress` reports as not `is_global` |

IPv4-mapped IPv6 (`::ffff:a.b.c.d`) is classified by its embedded IPv4 address. `sandbox_network` catches a daemon
configured with address pools outside RFC 1918; on a default daemon those networks are also `private`, and the more
specific name is the more useful one in a log.

**The hook.** `AddressGuard.server_connect(data)`, async:

- Enforce mode only. In log mode the guard classifies and logs `action: logged` without refusing, matching how log
  mode treats policy
- If `address[0]` parses as an IP literal, do nothing (open question 2)
- Resolve with `loop.getaddrinfo(host, port, type=SOCK_STREAM)`. On a resolution error, leave the connection alone;
  mitmproxy's own dial fails the same way and reports it
- If any answer is denied and not covered by `AGENTBOX_ADDRESS_GUARD_ALLOW`, set `data.server.error` to
  `agent-sandbox address guard: <host> resolves to <ip> (<class>); refused` and log the event. Any answer rather than
  the first, so a mixed answer cannot be steered onto its private half when the public half fails
- Otherwise remember the hostname on the connection, set `address` to the first answer, and restore it in
  `server_connected` and `server_connect_error`. mitmproxy's own log line then shows `host (ip)`

**Event.** One line per refusal, in the enforcer's JSON stream:
`{"type": "address_guard", "action": "blocked", "host": ..., "port": ..., "address": ..., "address_class": ...,
"answers": [...]}`. The `type` field sets it apart from policy decisions, which carry `reason` and no `type`.

**Escape hatch.** `AGENTBOX_ADDRESS_GUARD_ALLOW`, a comma-separated list of CIDRs, read at load like
`AGENTBOX_DNS_ALLOW`, set on the proxy service in `user.override.yml`. Addresses inside it pass. It is not in the
policy file, so the agent cannot reach it, and the renderer does not need to know about it. `m18.5` documents it.

**Tests.**

- Unit: every class in the table, both boundaries of each range, a mapped IPv4 address, public addresses in both
  families passing; the hook with a fake `data` and injected resolver for refuse, pin, restore on connected and on
  connect error, the any-answer rule, IP literals, the allow list, log mode, and a resolution error
- Integration, against the real `mitmdump`: policy allows `localhost`, which resolves to loopback on any machine,
  so the request is refused, the body names the guard, and the event names `loopback`. The other classes run
  through a test-only addon in the tests directory that swaps the guard's resolver for a fixed map, so a name can
  "resolve" to `10.0.0.1`, `169.254.169.254`, `fd00::1` without real DNS; the connection is refused before any
  packet, so the addresses never need to exist. Pinning is proven with a name that does not resolve on the system,
  mapped to `127.0.0.1` and allowed through `AGENTBOX_ADDRESS_GUARD_ALLOW=127.0.0.1/32`: the request can only reach
  the loopback upstream if the dial used the pinned address
- The existing integration tests stay as they are. They use `127.0.0.1` as a literal policy host, so under the
  literal exemption they need no hatch and prove the "no change" criterion for the proxy's normal paths

**Audit.** D3 and D4 send plain HTTP to `proxy:9` and `localhost:9` through the proxy. Today both read `http-502`
because the port refuses. `probe.bash` gains a `guard-refused` result when the body carries the guard's marker, and
`after-m18.4.tsv` expects it for both rows, replacing the planning-time guess of `http-403`. D3 is refused as
`sandbox_network` and D4 as `loopback`.

**Rollout.** Proxy image only. A user whose policy allows a name that resolves to a private address, such as an
internal Git server or a compose sidecar reached through the proxy, starts getting 502s with the guard's reason; the
changelog says so and names the environment variable. An agent image is unaffected.

**Residuals, for the decision record.** Pinning uses the first answer, so a host whose first address is unreachable no
longer falls back to the next. The guard trusts the answer the proxy container's resolver gives, which is Docker's
embedded resolver and the host's upstream. The DoH residual (D2) is untouched.

### Implementation Steps

- [ ] Spike the pin against `mitmdump` 12.2.3: SNI and verification, reuse, plain HTTP, and the refusal body on both
      paths. Record the result; fall back to option 1 if the pin does not hold
- [ ] Write `address_guard.py` with the classifier, the hook, and the allow list, and its unit tests
- [ ] Register it in `build_addons()`, add the harness's `extra_addons` and the resolver-swapping test addon, and write
      the integration tests
- [ ] Teach `probe.bash` the `guard-refused` result, update `after-m18.4.tsv`, the audit README, and the matrix
- [ ] Write the changelog entry and record the design choice in the milestone plan
- [ ] Maintainer rebuilds the proxy with `./images/build.sh proxy`, restarts it, and runs the audit at
      `--stage after-m18.4 --policy-probes` in CLI mode and against a devcontainer
- [ ] Verify each acceptance criterion, capture learnings, and note follow-ups for `m18.5`

### Open Questions

1. Pin (option 2) over check-only (option 1) or the request-phase 403 (option 3). Recommendation: option 2 if the
   spike holds. Option 1 leaves the rebinding window the milestone asked to close or record; option 3 doubles the
   resolution work for a friendlier status code
2. Exempt IP-literal hosts. Recommendation: yes. The threat is a name pointed somewhere unexpected; a literal in a
   policy the agent cannot edit is the operator saying where. It also keeps the existing integration tests free of any
   hatch. The cost is that a policy author who writes `169.254.169.254` gets exactly that
3. An operator allow list, `AGENTBOX_ADDRESS_GUARD_ALLOW`, beyond the tests' needs. The milestone said to add a hatch
   only if the tests need one and to keep it out of the authored policy. With question 2 the tests need none, but a
   user who allowlists `git.internal.example` on `10.x` has no other way through. Recommendation: add it, as an
   environment variable on the proxy service
4. 502 with the reason in the body, rather than 403. Recommendation: accept 502. It is what mitmproxy produces from the
   one hook every connection passes through, and it stays distinguishable from a policy 403, which the milestone
   wants. The audit matches the body marker, not the status
5. Refuse when any answer is denied, or only when the pinned one is. Recommendation: any. It is the stricter rule,
   easier to explain, and denies an attacker the choice of which half of a mixed answer the proxy uses
6. Whether `shared` (`100.64.0.0/10`) belongs in the deny set. It is carrier-grade NAT space, and Tailscale uses it. A
   proxy container does not route to a tailnet by default, so denying it costs nothing today. Recommendation: deny,
   and let the allow list cover a user who routes there

## Outcome

### Acceptance Verification

_Pending._

### Learnings

_Pending._

### Follow-up Items

_Pending._
