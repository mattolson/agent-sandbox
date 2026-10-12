# 009: DNS Is Answered By A Sinkhole In The Proxy, Not By Policy

## Status

Accepted

## Context

Before `m18`, every TCP connection from the agent container had to go through the proxy, but name resolution did not.
The agent resolved any name through Docker's embedded resolver at `127.0.0.11`, which forwarded unknown names to the
host and on to the internet. A nameserver an attacker controls sees every query name, so a lookup of
`<encoded-data>.attacker.example` carried data out without opening a connection the firewall would block, and `TXT`
answers carried data back. The `m18.1` audit demonstrated the channel end to end. It existed whatever the policy said,
because `init-firewall.sh` deliberately restored Docker's DNS NAT rules.

The audit also fixed two facts that shaped the options. On a user-defined network the stub at `127.0.0.11` is the only
source of compose service names, and the agent must keep resolving `proxy` for `HTTPS_PROXY` to work. And compose
`dns:` does not replace that stub; it sets the embedded resolver's upstream, and it takes only IP addresses.

## Decision

The agent resolves names only through a sinkhole served by the existing proxy container, and only compose service
names resolve.

- A mitmproxy DNS-mode addon (`dns_sinkhole.py`) listens on UDP and TCP port 5353 in the proxy container. It answers
  `proxy`, plus exact names listed in `AGENTBOX_DNS_ALLOW` on the proxy service, by resolving them through the proxy
  container's own resolver. Every other name gets `NXDOMAIN` immediately, without asking anyone.
- The agent's firewall rewrites port 53 to the sinkhole with a `nat` rule, rejects Docker's resolver address
  outright, rejects DNS and DNS-over-TLS to anything else, and points `/etc/resolv.conf` at the proxy.
- The firewall's self-test asserts both directions at every container start, one name that must resolve and one that
  must get `NXDOMAIN`, and refuses to start the container otherwise.
- There is no `dns:` key in the policy. Resolvable names follow the compose stack.
- IPv6 egress is denied outright except loopback (`m18.3`), so the sinkhole cannot be stepped around over a second
  address family.

## Rationale

**Why not a policy-driven resolver.** The obvious design lets the policy list names the agent may resolve. It is not
needed: the proxy resolves every allowed host on the agent's behalf, so a host in `domains` never requires the agent to
resolve it. A tool that resolves names itself is already bypassing the proxy, and making its lookup succeed would only
lead it to a connection the firewall refuses. A policy resolver would also have to forward allowed names upstream,
which reopens a query channel for every allowed zone, and it would add an authoring surface with no use. The one
legitimate need, reaching another compose service by name, is served by `AGENTBOX_DNS_ALLOW`, which follows the stack.

**Why in the proxy.** Four shapes were compared in `m18.2`:

1. Compose `dns:` pointed at a sidecar. The embedded resolver keeps answering service names and forwards the rest to
   the sidecar. It needs the sidecar at a fixed address, which needs a declared subnet, and two sandboxes on one host
   would collide on it. It also leaves the embedded resolver reachable on its real port.
2. A resolver sidecar reached through a rule installed at firewall start. It works, but a new service touches
   `depends_on`, healthchecks, both template layers, the checked-in runtime tree, and every command that reasons about
   services.
3. Binding port 53 in the proxy through an unprivileged-port sysctl. It needs a change to the managed compose layer,
   and those reach existing projects only through a fresh `agentbox init`.
4. A DNS listener in the existing proxy on an unprivileged port, reached through a port rewrite. No new service, no
   compose change, and the proxy already has the process, the logger, the tests, and the image pipeline.

Option 4 rolls out through `agentbox bump` alone, because both halves live in images.

**Why reject Docker's resolver outright.** The embedded resolver listens on `127.0.0.11` on a random high port, and the
port-53 NAT rule only redirects to it. Removing the NAT rule leaves the real port reachable; rejecting the address,
ahead of the loopback rule, closes both.

**Why deny IPv6 rather than mirror the IPv4 rules.** The agent reaches the proxy and the sinkhole over IPv4 by
construction, so mirrored IPv6 exceptions would have had no consumer, and they could only be tested with IPv6 enabled.
Disabling IPv6 on the network instead needs a managed-layer change and leaves a user who enables IPv6 unfiltered.

## Consequences

**Positive:**

- The query-name channel is closed regardless of policy. A name outside the stack never leaves the sandbox, verified by
  a capture in the Colima VM with a positive control.
- Tools that use `HTTPS_PROXY` are unaffected.
- Rollout is image-only.

**Negative:**

- A tool that resolves names itself now fails with `NXDOMAIN` instead of reaching the network. The fix is to route it
  through the proxy; `docs/troubleshooting.md` and the baked agent skill say so.
- Both images must be updated together. A new agent image against an old proxy refuses to start and says why; an old
  agent image against a new proxy keeps the previous behaviour.
- If the proxy is recreated with a new address while the agent keeps running, lookups fail until the agent restarts
  or re-runs `init-firewall.sh`.
- `mitmdump` in DNS mode crashed during interpreter teardown on mitmproxy 11.0.2. The proxy runs it through
  `run-mitmdump`, which exits without the teardown.

**Residual cases:**

- DNS-over-HTTPS to an allowed host resolves any name through that host. Recorded, not closed: it is a smaller case of
  the allowed-host channel, which the policy governs.
- The proxy container resolves the allowed hosts it connects to through its own resolver, so a lookup under an allowed
  wildcard reaches that zone's nameserver.
- Every compose service is reachable from the agent on any port, because the firewall allows the compose network so
  the proxy can be reached. A service that forwards traffic is an egress path; sidecars are trusted.

## Follow-up

- Document the boundary for users: `docs/network.md`.
- The address guard, which stops an allowed name being pointed at an internal address, is decision 010.
