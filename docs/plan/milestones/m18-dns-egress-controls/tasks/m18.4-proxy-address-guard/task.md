# Task: m18.4 - proxy address guard

## Summary

Refuse allowed hosts that resolve to addresses the sandbox should never reach.

## Scope

From the milestone plan, with the adjustments proposed under Approach and listed as open questions:

- At the point where the proxy opens an upstream connection, resolve the host, check every answer against a deny set
  (loopback, private, link-local including `169.254.169.254`, unique-local and link-local IPv6, the sandbox's own
  networks, and the other non-global ranges), and refuse the connection if any answer is denied
- Pin the dial to the checked addresses so a second resolution cannot hand mitmproxy a different one. The spike
  settled the mechanism: the checked answers are staged for the event loop's `getaddrinfo`, and mitmproxy's own dial
  consumes them; `server.address` is never touched
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
  - Requests inside a CONNECT tunnel take `request.host` from `server.address`: the layer inside the tunnel runs the
    transparent-mode branch (`proxy/layers/http/__init__.py:224`). Plain proxy requests take it from the request line.
    Measured in the spike: with the address rewritten, tunnelled requests carried `127.0.0.1` as their host
  - mitmproxy refuses to change `server.address` on an open connection (`Cannot change server.address on open
    connection`), so an address rewritten before the dial cannot be restored after it
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
- `images/proxy/tests/integration/harness.py`: an `extra_addons` parameter for that addon, a keep-alive TLS upstream
  that records SNI and client ports, a connection counter, the proxy CA path, and a CONNECT helper that reads the
  response body
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
2. Check and pin. The same check, then make the dial use exactly the answers that were checked. Two mechanisms were
   spiked. Rewriting `server.address` to the IP fails: it cannot be restored once the connection is open, and
   tunnelled requests then carry the IP as their host, so the policy would match against an address. Staging works:
   `server_connect` stores the checked answers under `(host, port)`, and a wrapper installed on the running event
   loop's `getaddrinfo` returns them when `asyncio.open_connection` resolves that key. The address stays the
   hostname, so SNI, certificate verification, connection reuse, and `request.host` are untouched, and because every
   checked answer is staged, `asyncio`'s fallback to the next address still works. The cost is a wrapper on one
   method of the loop instance, which relies on `asyncio` resolving through `loop.getaddrinfo`.
3. A request-phase check in the enforcer's `http_connect` and `requestheaders` hooks, answering 403 through the
   existing block path, plus option 2 underneath for the race. A familiar status code, but two resolutions per
   request, including requests on a connection that is already open and already checked, and two places that must
   agree.

This task takes option 2 with staging. The spike, on 2026-09-27 against `mitmdump` 12.2.3, is in the execution log.

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
- Otherwise stage every answer under `(host, port)` for a few seconds. The loop wrapper, installed in the guard's
  `running()` hook, returns staged answers for a staged key and passes every other lookup to the real
  `getaddrinfo`, including the sinkhole's and the guard's own. mitmproxy's log line then shows `host (ip)`

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
- Invariant tests, named `test_invariant_*`, pin the facts the design rests on and say so when they fail: asyncio's
  dial resolves through `loop.getaddrinfo`; the default loop accepts the wrapper; mitmproxy dials the tunnel and
  plain requests by hostname through asyncio, with SNI, Host, reuse, and `request.host` intact; a connection killed in
  `server_connect` receives no packet; and the CONNECT 502 can be replaced. Each was checked by mutation: breaking
  the invariant makes the test fail
- The existing integration tests stay as they are. They use `127.0.0.1` as a literal policy host, so under the
  literal exemption they need no hatch and prove the "no change" criterion for the proxy's normal paths

**Audit.** D3 and D4 send plain HTTP to `proxy:9` and `localhost:9` through the proxy. Today both read `http-502`
because the port refuses. After this task they get the request-phase 403. `probe.bash` gains a `guard-refused`
result when the body carries the guard's marker, so the row proves the guard and not just some 403, and
`after-m18.4.tsv` expects it for both rows. D3 is refused as `sandbox_network` and D4 as `loopback`.

**Rollout.** Proxy image only. A user whose policy allows a name that resolves to a private address, such as an
internal Git server or a compose sidecar reached through the proxy, starts getting 403s with the guard's reason; the
changelog says so, and tells sidecar users to use `NO_PROXY`. An agent image is unaffected.

**Residuals, for the decision record.** Pinning depends on `asyncio` resolving through the loop's `getaddrinfo`,
which the pinned mitmproxy and Python versions do and an integration test proves on every run. The guard trusts the answer the proxy container's resolver gives, which is Docker's
embedded resolver and the host's upstream. The DoH residual (D2) is untouched.

### Implementation Steps

- [x] Spike the pin against `mitmdump` 12.2.3: SNI and verification, reuse, plain HTTP, and the 403 swap in
      `http_connect_error`. Address rewriting failed; staging answers for the loop's `getaddrinfo` holds
- [x] Write `address_guard.py` with the classifier and the hook, and its unit tests
- [x] Register it in `build_addons()`, add the enforcer's `http_connect_error` swap and the plain-`http` pre-check,
      add the harness's `extra_addons` and the resolver-swapping test addon, and write the integration tests
- [x] Teach `probe.bash` the `guard-refused` result, update `after-m18.4.tsv`, the audit README, and the matrix
- [x] Write the changelog entry and record the design choice in the milestone plan
- [x] Maintainer rebuilds the proxy with `./images/build.sh proxy`, restarts it, and runs the audit at
      `--stage after-m18.4 --policy-probes` in CLI mode and against a devcontainer
- [x] Verify each acceptance criterion, capture learnings, and note follow-ups for `m18.5`

### Open Questions

1. Resolved 2026-09-27: pin (option 2), by staging checked answers for the loop's `getaddrinfo`, after the spike
   showed that rewriting `server.address` breaks tunnelled requests
2. Resolved 2026-09-27: IP-literal hosts are exempt
3. Resolved 2026-09-27: no operator hatch for now. The tests need none, sidecars have `NO_PROXY`, and a hatch is
   easier to add than to take back. If a user reports an internal host, add a name-scoped variable on the proxy
   service, not a CIDR list
4. Resolved 2026-09-27: 403, not 502. A guard refusal is the proxy refusing, deterministically, and 502 reads as an
   upstream fault that invites a retry. The body and the event distinguish it from a policy block. CONNECT gets the
   403 by replacing mitmproxy's 502 in `http_connect_error`; plain `http` gets it from a request-phase pre-check. A
   502 remains only where the answer changes between the pre-check and the connect, and for a new connection opened
   by a decrypted request, which is rare because those reuse the tunnel's connection
5. Resolved 2026-09-27: refuse when any answer is denied
6. Resolved 2026-09-27: `shared` (`100.64.0.0/10`, carrier-grade NAT, used by Tailscale) is denied; a user who
   routes there is a case for the name-scoped hatch

## Outcome

### Acceptance Verification

Evidence is the audit on 2026-09-27 in CLI mode (`results/after-m18.4-20260927-172036/`) and devcontainer mode
(`results/after-m18.4-20260927-172535/`), both with `--policy-probes` and IPv6 on, and the proxy suite, 269 tests,
on the pinned mitmproxy 12.2.3.

- [x] A host on the allowlist whose DNS answer is a private or link-local address is refused, with a log event
      naming the address class. In both modes D3 is refused as `sandbox_network` and D4 as `loopback`, each with a
      403 naming the guard; the integration tests refuse every class, including `private`, `link_local`, and
      `metadata`, each named in the body and the `address_guard` event
- [x] The existing integration harness, which rebinds rendered hosts onto loopback, still passes, either through the
      documented escape hatch or by an explicit test-only configuration. All pre-existing integration tests pass
      unchanged: they write `127.0.0.1` as the policy host, and IP-literal hosts are exempt. The guard's own tests
      use a test-only addon loaded through the harness
- [x] No change in behavior for hosts that resolve to ordinary public addresses. Public addresses in both families
      classify as allowed in the unit tests; pinned dials keep SNI, Host, connection reuse, and `request.host`
      (integration); and in the live audit D2 still reaches `dns.google` through the proxy
- [x] Proxy unit and integration tests cover each refused address class. Unit: every class at both ends of each
      range, mapped IPv4, and zone suffixes. Integration: one refused request per class against the real `mitmdump`

### Learnings

- Spike a mechanism against the real dependency before building on it. Reading mitmproxy's source suggested
  rewriting `server.address` would work; running it showed the address cannot change on an open connection and
  that tunnelled requests take their host from it. Neither was visible from reading alone
- Check the harness with a direct control before blaming the design. The spike's first HTTPS failure was the test
  upstream's `sni_callback` returning an integer, which Python's `ssl` treats as a TLS alert; curl straight to the
  upstream reproduced it without the proxy
- A test that guards an invariant must be checked by breaking the invariant. The first unit invariant test failed
  for an unrelated reason and blamed asyncio. Mutation runs, one per invariant, showed each test fails for the
  reason its message gives
- `server_connect` is the one mitmproxy hook every upstream connection passes through, and the only one that can
  refuse before the dial. `server_connected` cannot abort, and a plain request's error response cannot be replaced
  from the `error` hook, while a CONNECT's can be from `http_connect_error`
- Pinning by staging answers for the loop's `getaddrinfo` keeps mitmproxy's connection state untouched, and staging
  every checked answer preserves asyncio's fallback across addresses
- With IPv6 on the network, the proxy's lookups return AAAA first. Refusing on any denied answer made the order
  irrelevant; both live refusals named the IPv6 address
- Two audit rows that share a target but expect different policies stay hidden until a run exercises both. D1 and
  D2 had conflicted since `m18.1`

### Follow-up Items

- `m18.5`: document the guard: what it refuses, the 403 body and the `address_guard` event, the IP-literal
  exemption, and `NO_PROXY` for sidecars reached through the proxy. The decision record should carry the three
  designs, the spike that ruled out rewriting the address, the staging monkeypatch and the invariant tests that
  gate it, and the residuals: the guard trusts the proxy container's resolver, and DoH to an allowed host (D2)
  stays open
- Add a name-scoped exemption on the proxy service the first time a user reports an internal allowed host
- `images/build.sh` treats an unknown first argument as `all` and passes it on to `docker buildx build`, so a typo
  such as `proxy,` builds everything and then fails with a confusing Docker error. Reject unknown targets instead;
  outside this milestone
- The branch has no pull request, so none of the `m18.2` through `m18.4` proxy changes has run in CI
