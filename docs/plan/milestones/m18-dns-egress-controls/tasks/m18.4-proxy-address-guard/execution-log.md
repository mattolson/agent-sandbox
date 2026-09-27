# Execution Log: m18.4 - proxy address guard

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
