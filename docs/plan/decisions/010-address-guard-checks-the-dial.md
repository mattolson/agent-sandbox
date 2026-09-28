# 010: The Address Guard Checks The Dial's Own Lookup

## Status

Accepted

## Context

The proxy connects to whatever address an allowed name resolves to. The `m18.1` audit showed it: an allowed `proxy`
resolved to the proxy's own compose address and `localhost` to loopback, and the proxy dialled both. So a name on the
allowlist could be pointed at the cloud metadata endpoint, the host network, or a service on the compose network, and
the proxy would reach it on the agent's behalf. The policy decides which names may be reached; nothing decided which
addresses those names may resolve to.

Two constraints shaped the design. The check has to happen where the proxy opens the upstream connection, for CONNECT
tunnels and plain requests alike. And a check that resolves the name separately from the connection has a gap: a
nameserver can answer a public address to the check and a private one to the connection.

## Decision

The proxy refuses any upstream connection to a named host if any of its DNS answers is loopback, private, link-local,
a cloud metadata address, unique-local IPv6, carrier-grade NAT space, the sandbox's own network, unspecified,
multicast, or otherwise not public. The check runs inside the connection's own lookup.

- mitmproxy opens every upstream connection with `asyncio.open_connection(host, port)`, which resolves through the
  running event loop's `getaddrinfo`. The guard (`address_guard.py`) replaces that one method on that one loop with a
  wrapper. For a lookup made to open a connection, the wrapper classifies every answer and raises `AddressRefused`, an
  `OSError`, before any socket opens if one is denied. Otherwise it returns the answers, and asyncio connects to
  exactly those.
- Lookups that are not connections pass through: the DNS sinkhole's, which carry no port, and a server's bind to every
  interface, which asyncio resolves with no host and `AI_PASSIVE`.
- The client gets the proxy's `403` with a body naming the guard, the address, and its class, and the proxy logs an
  `address_guard` event. On a CONNECT the enforcer replaces mitmproxy's `502` in `http_connect_error`. A plain `http`
  request's connection opens after the request hooks, where mitmproxy's error response cannot be replaced, so the
  guard checks those requests first and the enforcer answers `403`.
- Hosts written as IP addresses are not checked.
- There is no operator exemption.

## Rationale

**Why check the dial's own lookup.** Five designs were considered in `m18.4`:

1. Check, then let mitmproxy dial. Simple, but the dial resolves the name again, which is the rebinding window.
2. Rewrite `server.address` to the checked IP before the dial. Spiked against mitmproxy 12.2.3 and rejected: the
   address cannot be changed back once the connection is open, and requests inside a CONNECT tunnel take their host
   from it, so the policy would have matched against an IP.
3. Stage the checked answers for the dial's lookup to consume. Built first, and replaced after the review of #204:
   the wrapper passed any lookup without a live staged entry to the real resolver, unchecked, and an entry could be
   missing because the lookup failed, because it expired while the dial waited on mitmproxy's per-address connection
   semaphore, or because another connection to the same host overwrote it.
4. Check before the dial, then verify the connected peer address. It uses only documented hooks, but
   `server_connected` cannot abort a connection, so a plain request in a rebinding race would still reach the address.
5. Check the answers inside the dial's own lookup. The check and the connection are the same lookup, so nothing can
   expire, be missing, or be shared, and nothing is sent to a denied address.

Option 5 was chosen. It replaces a method on an object mitmproxy owns, and it depends on asyncio resolving connections
through `loop.getaddrinfo`, which is an implementation detail rather than a documented contract. The maintainer
accepted that on one condition: tests must fail on any Python or mitmproxy upgrade that breaks the facts it relies on.
The `test_invariant_*` tests do, and each was confirmed by breaking its invariant on purpose.

**Why refuse on any answer.** A host with one public and one private answer is refused, so an attacker cannot make the
public address fail and steer the connection onto the private one.

**Why 403, not 502.** A guard refusal is the proxy refusing, and it is deterministic; retrying cannot succeed. 502 reads
as an upstream fault and invites a retry. The body and the log distinguish it from a policy block.

**Why IP literals are exempt.** The guard protects a name from being pointed somewhere unexpected. An address written
in a policy the agent cannot edit is the operator stating where; it also leaves the proxy's integration tests, which
allow `127.0.0.1`, free of any exemption.

**Why no operator exemption yet.** The tests need none, a compose sidecar can be reached directly through `NO_PROXY`,
and an exemption is easier to add when someone needs it than to take back once shipped. If one is added, it should
name hosts allowed to resolve privately, not address ranges: allowing `10.0.0.0/8` for one server would admit any
other allowed name that resolves there.

## Consequences

**Positive:**

- An allowed name cannot be used to reach metadata, loopback, the host network, or the compose network through the
  proxy, including through a nameserver that changes its answer between lookups.
- Nothing about mitmproxy's connection state changes: SNI, certificate verification, connection reuse, and
  `request.host` stay on the hostname.
- Behaviour for hosts that resolve to public addresses is unchanged.

**Negative:**

- A policy that allows an internal host, such as a Git server on a private address, stops working, with no exemption
  yet. The changelog says so.
- A plain `http` request to a named host is resolved twice: once to answer `403` early, once by the connection. If the
  answer changes between them, the connection is still refused, but with mitmproxy's `502`.
- The design depends on the running event loop accepting an instance attribute and on asyncio's resolution path. Both
  are pinned by tests, and mitmproxy and Python are pinned in the image.

**Residual cases:**

- The guard checks the answers the proxy container's resolver returns and trusts that resolver.
- Allowed hosts still carry whatever the agent sends them; the guard is about where a name leads, not what it carries.

## Follow-up

- Add a name-scoped exemption on the proxy service the first time a user reports an internal allowed host.
