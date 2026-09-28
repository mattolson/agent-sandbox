# Network Boundary

What the agent container can reach, what refuses the rest, and what a refusal looks like from inside. The policy
file format is in [policy/schema.md](./policy/schema.md); fixes for each failure are in
[troubleshooting.md](./troubleshooting.md).

## The four layers

A request from the agent meets these in order.

1. **Firewall** (`init-firewall.sh`, in the agent container). Direct outbound is refused, so every connection must go
   to the compose network, where the proxy runs. IPv6 is refused entirely except loopback (`::1`); the agent reaches
   the proxy over IPv4. A refused connection fails at once: `Operation not permitted` on a UDP send,
   `No route to host` on an IPv4 TCP connect, `Permission denied` on an IPv6 one.
2. **DNS sinkhole** (in the proxy container). The agent can resolve only the compose service names it needs: `proxy`,
   plus any names in `AGENTBOX_DNS_ALLOW`. Every other name gets `NXDOMAIN` immediately. Docker's embedded resolver is
   unreachable, and DNS or DNS-over-TLS to anything else is refused by the firewall. Tools that use `HTTPS_PROXY`
   never notice, because the proxy resolves allowed hosts on their behalf; only a tool that resolves names itself
   sees the `NXDOMAIN`.
3. **Proxy policy** (`enforcer.py`). The allowed hosts and request rules from your policy files. A refused request gets
   `403` with the body `Blocked by proxy policy: <host>`; for HTTPS the `CONNECT` is refused before the tunnel opens.
4. **Address guard** (`address_guard.py`, in the proxy). An allowed name that resolves to a loopback, private,
   link-local, cloud-metadata, unique-local IPv6, carrier-grade NAT, or other non-public address is refused before the
   proxy connects. The client gets `403` with the body
   `agent-sandbox address guard: <host> resolves to <address> (<class>); refused`. Hosts written as IP addresses in the
   policy are not checked: an address in a policy the agent cannot edit is the operator's explicit choice.

The firewall checks all of this at every container start and refuses to start if a check fails; see
[Startup checks](#startup-checks).

## Why DNS is locked down

Before these controls, the agent resolved any name through Docker's embedded resolver, which forwarded it to the host
and on to the internet. A nameserver an attacker controls sees every query name, so a lookup of
`<encoded-data>.attacker.example` carries data out without the agent opening a single connection the firewall would
block, and `TXT` answers carry data back in. That channel existed regardless of policy.

Now a name outside the compose stack never leaves the sandbox: the sinkhole answers `NXDOMAIN` itself and asks no one.
The address guard closes a related path, where an allowed name is pointed at an internal address, such as the cloud
metadata endpoint or a service on the host network, to make the proxy reach something it should not.

This removes channels that existed whatever the policy said. It does not reduce what an allowed host can carry, which
is the larger channel; see [Residual cases](#residual-cases).

## What failures look like

| Symptom inside the container | Layer | Meaning |
|------------------------------|-------|---------|
| `Could not resolve host`, `ENOTFOUND`, `NXDOMAIN`, `Name or service not known` | Sinkhole | The tool resolved a name itself instead of using the proxy |
| `Couldn't connect to server` (curl), `Operation not permitted`, `No route to host`, `Permission denied` | Firewall | A direct connection that bypassed the proxy |
| `403`, `Blocked by proxy policy: <host>` | Proxy policy | The host or request is not on the allowlist |
| `403`, `agent-sandbox address guard: ... refused` | Address guard | An allowed name resolved to an internal address |

For HTTPS both kinds of `403` arrive on the `CONNECT`, and most clients show only the status (curl:
`CONNECT tunnel failed, response 403`). The proxy log says which layer refused.

The proxy logs each refusal as a JSON line, which `agentbox proxy logs` shows:

- Sinkhole: `{"type": "dns", "action": "nxdomain", "name": "...", "qtype": "A", "client": "..."}`
- Proxy policy: `{"phase": "connect", "action": "blocked", "reason": "host_not_allowed", "host": "...", ...}`
- Address guard: `{"type": "address_guard", "action": "blocked", "phase": "connect", "host": "...", "port": 443,
  "address": "...", "address_class": "...", "answers": [...]}`

## Tools that resolve names themselves

Most tools send requests to `HTTPS_PROXY` and let the proxy resolve the name, so they are unaffected. A tool that
resolves the name itself gets `NXDOMAIN`. Such a tool already failed before the sinkhole existed, because the firewall
refused its direct connection; only the error changed. The fix is to configure the tool to use the proxy, not to allow
the name.

Measured against the sinkhole: `curl`, `git`, Python's `urllib`, `pip`, `uv`, `npm`, `go`, `cargo`, and `rustup` use the
proxy. Node's built-in `fetch` does not: on Node 22 it fails with `ENOTFOUND`. Setting `NODE_USE_ENV_PROXY=1` makes it
use the proxy; Node then prints an "EnvHttpProxyAgent is experimental" warning, and a host the proxy refuses shows up
as `fetch failed` with the cause `Request was cancelled.` rather than a 403.

`scripts/dns-egress-audit/tool-probe.bash` reports which installed tools use the proxy. Run it inside a sandbox with
`docker exec -i <agent container> bash -s < scripts/dns-egress-audit/tool-probe.bash`.

## Sidecars

To reach another compose service by name, the agent needs two things:

- The name must resolve. Add it to `AGENTBOX_DNS_ALLOW` on the proxy service, a comma-separated list of exact names.
- HTTP clients must connect to it directly rather than through the proxy, because the proxy's address guard refuses
  the sidecar's private address. Add the name to `NO_PROXY` on the agent service, keeping the defaults.

Both go in `.agent-sandbox/compose/user.override.yml`:

```yaml
services:
  proxy:
    environment:
      - AGENTBOX_DNS_ALLOW=db-api
  agent:
    environment:
      - NO_PROXY=localhost,127.0.0.1,proxy,db-api
```

The firewall allows the compose network in both directions, which is how the agent reaches the proxy. Every service on
that network is therefore reachable from the agent on any port, and any of them that forwards traffic onward is an
egress path the proxy does not see. Treat sidecars as trusted egress.

There is no exemption for other internal hosts yet. A policy that allows a name resolving to a private address, such
as an internal Git server, is refused by the address guard.

## Startup checks

The firewall prints its checks to the container log at every start. A healthy start ends with:

```
PASS: unknown name refused with NXDOMAIN (sinkhole-test-<random>.invalid)
PASS: Direct outbound blocked (1.1.1.1 unreachable)
Verifying IPv6...
PASS: IPv6 absent on eth0; ip6tables default-deny covers it if the network gains it
PASS: IPv6 loopback open (::1)

Firewall initialization complete.
```

With IPv6 enabled on the compose network, the IPv6 lines read `PASS: IPv6 UDP/53 to a public resolver rejected` and
`PASS: IPv6 TCP/53 to a public resolver rejected` instead of the `absent` line. Any `FAIL` or `ERROR` stops the container
with a `FATAL: Firewall initialization failed!` banner.

## Upgrades and version skew

The controls span both images: the firewall and startup checks live in the agent image, the sinkhole and the address
guard in the proxy image. Update both with `agentbox bump`.

- A new agent image against an old proxy image refuses to start: the DNS check finds no sinkhole, and the banner says
  to run `agentbox bump`.
- An old agent image against a new proxy image keeps the previous behaviour, with DNS unrestricted, because nothing
  points it at the sinkhole.

If the proxy container is recreated with a new address while the agent keeps running, every lookup in the agent fails,
including `proxy` itself. Restart the agent container (`agentbox compose restart agent`), or re-run the firewall in
place from inside it with `sudo /usr/local/bin/init-firewall.sh`.

## Residual cases

These remain open, by design or because closing them is a different problem:

- **Allowed hosts carry data.** Anything the policy allows can receive whatever the agent sends it. The DNS controls do
  not change that; the policy is the control.
- **DNS-over-HTTPS to an allowed host.** If a DoH provider such as `dns.google` is allowed, the agent can resolve any
  name through it, and the query reaches that name's nameserver. Do not allow DoH providers unless you need them.
- **The proxy's own lookups.** The proxy resolves the allowed hosts it connects to through its own resolver. A query for
  a name under an allowed wildcard reaches that zone's nameserver, which matters only if someone else controls a zone
  your policy allows.
- **The address guard trusts the proxy's resolver.** It checks the answers the proxy container receives.
- **Sidecars are trusted egress**, as described under [Sidecars](#sidecars).
- **The IDE control plane in devcontainer mode** is separate from this data plane; see the README.

## Verifying

`scripts/dns-egress-audit/` probes every channel from a running sandbox and compares the result with the expected
state; its README has the procedure. The firewall's startup checks run on every container start, and the proxy's
unit and integration tests cover the sinkhole and the address guard.
