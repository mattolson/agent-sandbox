# Execution Log: m18.4 - proxy address guard

## 2026-09-27 - Implemented and tested from the sandbox

The maintainer accepted the `getaddrinfo` wrapper on the condition that tests fail on any version bump that breaks
the invariants it relies on. `address_guard.py`, the enforcer wiring, 36 unit tests, and 8 integration tests are in;
the full proxy suite runs 269 tests, all passing. The audit reports `guard-refused` for D3 and D4.

**Decision:** The plain-`http` pre-check lives in the guard's own async `requestheaders` hook, ordered after the
enforcer, with a callback into the enforcer to store a blocked decision and set the 403. The enforcer's request
hooks are synchronous and its unit tests call them that way; making them async to await a lookup would have
rewritten those tests. The stored decision keeps the enforcer's response hook from logging the flow as allowed.

**Decision:** The guard takes `resolver` and `classifier` as constructor parameters. The unit tests inject them, and
the integration tests' test-only addon replaces them on the running guard, so production carries no test-specific
environment variable or flag.

**Issue:** The first version of the unit invariant test failed with a message saying asyncio no longer resolved
through the loop. The real cause was the test: it cleared the deny table to let `127.0.0.1` through, but the
catch-all `not is_global` rule still classified it `reserved`, so nothing was staged. A test that misreports a
broken invariant is worse than none. It now stages the answer directly and tests only the asyncio fact.

**Observation:** Mutation checks. Simulating an asyncio that resolves through `socket.getaddrinfo` instead of the
loop method fails the unit invariant test with its message. With the wrapper installed but ignored, both integration
pinning tests fail. With the enforcer's `http_connect_error` swap removed, the refused-CONNECT test fails on the
502. Source files were restored after each run.

**Issue:** `send_connect_and_wait` stops at the end of the headers, so the refused CONNECT's body looked empty. The
harness gained `send_connect_full`, which reads to close.

## 2026-09-27 - Spike: rewriting the address fails, staging answers pins

Approved with IP literals exempt, no operator hatch, any-answer refusal, `100.64.0.0/10` denied, and 403 for
refusals. Spiked against `mitmdump` 12.2.3 with a local TLS upstream whose certificate names `pinned.test` and
`blocked.test`, neither of which resolves on this machine, trusted through `ssl_verify_upstream_trusted_ca`, and curl
as the client. A request to either name can only succeed if the proxy dialled an address the addon supplied.

**Issue:** The first HTTPS runs failed with `Server TLS handshake failed. connection closed`, which looked like the
design failing. Direct curl to the upstream without the proxy failed the same way. The harness's `sni_callback`
returned `log.write(...)`, an integer, and Python's `ssl` treats any non-`None` return as a TLS alert. Fixed in the
harness; every result below is from the fixed run.

**Observation:** Rewriting `server.address` in `server_connect` and restoring it in `server_connected` does not work.
The restore raises `Cannot change server.address on open connection`, so the address stays the IP, and requests
inside the tunnel took their host from it: `https://127.0.0.1:52463/one`. The request reached the upstream, with SNI
`pinned.test` supplied from the client, but the enforcer would have matched the policy against `127.0.0.1`. This also
corrects the planning entry above: line 224's branch does run for tunnelled requests, because the layer inside a
CONNECT tunnel takes the transparent-mode path. The first reading was right and the "correction" was wrong.

**Observation:** Staging holds. `server_connect` stored the answers under `(host, port)`; a wrapper assigned to the
running loop's `getaddrinfo` returned them when mitmproxy dialled. Result: HTTPS 200 for two requests on one tunnel
over one upstream connection with one lookup; SNI `pinned.test`; `request.host` `pinned.test`; peer `127.0.0.1`;
plain HTTP 200, pinned the same way. mitmproxy logs `server connect pinned.test:44641 (127.0.0.1:44641)`.

**Observation:** The 403 swap works. With `server.error` set, `http_connect_error` fired with mitmproxy's 502 in
`flow.response`; replacing it delivered `403 Forbidden` with the guard's body to the CONNECT client. A plain request
to the refused name got mitmproxy's 502 with `Connection killed: agent-sandbox address guard: ...` in the body, as
expected, which is what the request-phase pre-check replaces.

**Decision:** Pin by staging. Because every checked answer is staged, `asyncio`'s fallback to the next address keeps
working, which removes a residual the plan had listed.

## 2026-09-27 - Planning

Read mitmproxy 12.2.3's connection path from the installed source. `server_connect` is the single point every
upstream connection passes through, and it can kill a connection before the dial by setting `server.error`.
`server_connected` cannot abort, so checking the real peer address after the connect is not an option without
reaching into mitmproxy's transports.

**Issue:** First read of `proxy/layers/http/__init__.py:226` suggested that rewriting `server.address` would change
`request.host` for tunnelled requests and break policy matching. That line runs in transparent mode only; the proxy
runs in regular mode, where the host comes from the request. Corrected before it shaped the plan. What a lasting
rewrite does break is connection reuse, which matches on `address`, and the SNI fallback on the eager CONNECT
connection. Restoring the hostname in `server_connected` avoids both.

**Observation:** The integration tests do not rebind names. They write `127.0.0.1` as the policy host and run their
upstreams on loopback. A guard that also checked IP literals would refuse every one of them.

**Observation:** D3 and D4 already read `http-502` today, because the proxy dials `proxy:9` and `localhost:9` and the
ports refuse. A guard that answers with mitmproxy's 502 needs the audit to match the body, not the status.

**Decision (proposed):** check and pin in `server_connect`, exempt IP literals, add an operator CIDR allow list on the
proxy service. Six open questions in `task.md`. Awaiting approval.
