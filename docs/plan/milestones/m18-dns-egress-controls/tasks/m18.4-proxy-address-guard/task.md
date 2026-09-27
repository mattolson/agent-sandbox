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
- Emit a distinct structured event naming the host, the address, and the address class, and answer the client with
  the proxy's 403 and a body that names the guard and the reason
- Proposed: hosts written as IP literals are exempt. The guard protects an allowed name from being pointed somewhere
  unexpected; a literal is an explicit address in a policy the agent cannot edit
- No operator escape hatch in this task (decided 2026-09-27). The tests need none under the literal exemption, and a
  hatch is easier to add on demand than to remove once shipped. Users with an allowed host that resolves privately
  are told in the changelog; a name-scoped hatch is the follow-up if one reports it
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
  - A killed connection reaches the client as a 502 that mitmproxy builds itself. On a CONNECT, the
    `http_connect_error` hook fires with that 502 in `flow.response` before it is sent (`http/__init__.py:827`), so an
    addon can replace it. On a plain or decrypted request the failure goes through `ResponseProtocolError` with
    `CONNECT_FAILED`; the `error` hook fires but cannot replace what is sent
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
- `images/proxy/addons/enforcer.py`: register the guard in `build_addons()` beside the sinkhole; an
  `http_connect_error` hook that turns the guard's 502 into the enforcer's 403; a request-phase check for plain
  `http` requests; document the new environment variable in the module docstring
- `images/proxy/tests/test_address_guard.py` (new): classifier and hook unit tests with an injected resolver
- `images/proxy/tests/integration/test_address_guard.py` (new) and a test-only addon under
  `images/proxy/tests/integration/` that replaces the guard's resolver, loaded with an extra `-s` by the harness
- `images/proxy/tests/integration/harness.py`: an `extra_addons` parameter for that addon
- `scripts/dns-egress-audit/probe.bash`: D3 and D4 recognise the guard's marker in the response body
- `scripts/dns-egress-audit/expected/after-m18.4.tsv`, `README.md`, and the milestone's `bypass-matrix.md`
- `CHANGELOG.md`: an `[Unreleased]` entry that says allowed hosts resolving to private addresses are now refused,
  and points sidecar users at `NO_PROXY`
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
plain HTTP request is pinned the same way, (d) replacing the 502 in `http_connect_error` delivers a 403 with the
enforcer's body to a CONNECT client. If (a) through (c) fail, fall back to option 1 and record the residual; if (d)
fails, CONNECT refusals stay 502 and the plan says so.

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
- If any answer is denied, set `data.server.error` to
  `agent-sandbox address guard: <host> resolves to <ip> (<class>); refused` and log the event. Any answer rather than
  the first, so a mixed answer cannot be steered onto its private half when the public half fails
- Otherwise remember the hostname on the connection, set `address` to the first answer, and restore it in
  `server_connected` and `server_connect_error`. mitmproxy's own log line then shows `host (ip)`

**Status code.** The client gets 403, the same status as a policy block, because a guard refusal is the proxy
refusing and a retry cannot succeed; 502 reads as an upstream fault and invites one. The body and the event say it
was the guard. Two paths get there:

- CONNECT, which carries nearly all HTTPS traffic: `server_connect` refuses the eager dial, mitmproxy prepares its
  502, and the enforcer's `http_connect_error` hook replaces it with the 403 when the connection error carries the
  guard's marker. One resolution, in `server_connect`
- Plain `http` requests: the connection opens after the request hooks, and the `error` hook cannot replace the 502
  mitmproxy sends. So the enforcer's `requestheaders` path runs the guard's check first for `http` requests only and
  blocks with 403 through the existing block path. `server_connect` still checks and pins when the connection opens,
  so a plain request resolves twice; if the answer changes between the two, the second check refuses with a 502.
  Decrypted requests inside a tunnel are not pre-checked: they normally reuse the connection the CONNECT already
  checked, and a new connection they open is still checked and pinned, with a 502 on refusal

**Event.** One line per refusal, in the enforcer's JSON stream:
`{"type": "address_guard", "action": "blocked", "phase": "connect" | "request", "host": ..., "port": ...,
"address": ..., "address_class": ..., "answers": [...]}`. The `type` field sets it apart from policy decisions, which
carry `reason` and no `type`. The 403 body starts with `agent-sandbox address guard:` and names the host, address,
and class.

**No escape hatch.** Nothing lets an operator exempt a name or a range. Of the cases that would want one, a compose
sidecar reached through the proxy has a workaround: list its name in `NO_PROXY` on the agent service, and the agent
connects directly over the host network the firewall already allows. An internal host such as a Git server on `10.x`
has none; if a user reports one, the follow-up is an environment variable on the proxy service that names hosts
allowed to resolve privately. Names rather than CIDRs, because allowing `10.0.0.0/8` for one server would also admit
any other allowed name that resolves there.

**Tests.**

- Unit: every class in the table, both boundaries of each range, a mapped IPv4 address, public addresses in both
  families passing; the hook with a fake `data` and injected resolver for refuse, pin, restore on connected and on
  connect error, the any-answer rule, IP literals, log mode, and a resolution error
- Integration, against the real `mitmdump`: policy allows `localhost`, which resolves to loopback on any machine,
  so the request is refused, the body names the guard, and the event names `loopback`. The other classes run
  through a test-only addon in the tests directory that swaps the guard's resolver for a fixed map, so a name can
  "resolve" to `10.0.0.1`, `169.254.169.254`, `fd00::1` without real DNS. Both paths are covered: an HTTPS
  CONNECT and a plain HTTP request each get a 403 with the guard's body. The connection is refused before any
  packet, so the addresses never need to exist. Pinning is proven with a name that does not resolve on the system,
  mapped by the test addon to `127.0.0.1`, with the same addon removing `loopback` from the guard's deny table for
  that test only: the request can only reach the loopback upstream if the dial used the pinned address. Both
  overrides live in the tests directory and are loaded with `-s`, so production carries no test hook
- The existing integration tests stay as they are. They use `127.0.0.1` as a literal policy host, so under the
  literal exemption they need no hatch and prove the "no change" criterion for the proxy's normal paths

**Audit.** D3 and D4 send plain HTTP to `proxy:9` and `localhost:9` through the proxy. Today both read `http-502`
because the port refuses. After this task they get the request-phase 403. `probe.bash` gains a `guard-refused`
result when the body carries the guard's marker, so the row proves the guard and not just some 403, and
`after-m18.4.tsv` expects it for both rows. D3 is refused as `sandbox_network` and D4 as `loopback`.

**Rollout.** Proxy image only. A user whose policy allows a name that resolves to a private address, such as an
internal Git server or a compose sidecar reached through the proxy, starts getting 403s with the guard's reason; the
changelog says so, and tells sidecar users to use `NO_PROXY`. An agent image is unaffected.

**Residuals, for the decision record.** Pinning uses the first answer, so a host whose first address is unreachable no
longer falls back to the next. The guard trusts the answer the proxy container's resolver gives, which is Docker's
embedded resolver and the host's upstream. The DoH residual (D2) is untouched.

### Implementation Steps

- [ ] Spike the pin against `mitmdump` 12.2.3: SNI and verification, reuse, plain HTTP, and the 403 swap in
      `http_connect_error`. Record the result; fall back to option 1 if the pin does not hold
- [ ] Write `address_guard.py` with the classifier and the hook, and its unit tests
- [ ] Register it in `build_addons()`, add the enforcer's `http_connect_error` swap and the plain-`http` pre-check,
      add the harness's `extra_addons` and the resolver-swapping test addon, and write the integration tests
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
3. Resolved 2026-09-27: no operator hatch for now. The tests need none, sidecars have `NO_PROXY`, and a hatch is
   easier to add than to take back. If a user reports an internal host, add a name-scoped variable on the proxy
   service, not a CIDR list
4. Resolved 2026-09-27: 403, not 502. A guard refusal is the proxy refusing, deterministically, and 502 reads as an
   upstream fault that invites a retry. The body and the event distinguish it from a policy block. CONNECT gets the
   403 by replacing mitmproxy's 502 in `http_connect_error`; plain `http` gets it from a request-phase pre-check. A
   502 remains only where the answer changes between the pre-check and the connect, and for a new connection opened
   by a decrypted request, which is rare because those reuse the tunnel's connection
5. Refuse when any answer is denied, or only when the pinned one is. Recommendation: any. It is the stricter rule,
   easier to explain, and denies an attacker the choice of which half of a mixed answer the proxy uses
6. Whether `shared` (`100.64.0.0/10`) belongs in the deny set. It is carrier-grade NAT space, and Tailscale uses it. A
   proxy container does not route to a tailnet by default, so denying it costs nothing today. Recommendation: deny;
   a user who routes there is a case for the name-scoped hatch

## Outcome

### Acceptance Verification

_Pending._

### Learnings

_Pending._

### Follow-up Items

_Pending._
