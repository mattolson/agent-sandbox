# Execution Log: m18.2 - dns sinkhole

## 2026-09-12 - Planning: design settled by two spikes and one rollout fact

**Observation:** The embedded resolver listens on a random high port on `127.0.0.11`, and the port-53 NAT rule only
redirects to it. Raw queries to that port answer and forward upstream. Recorded as audit rows A9 and A10, and the
after-m18.2 values for the raw rows changed from `nxdomain` to `rejected`, because the design now rejects the
address rather than removing a redirect.

**Observation:** mitmproxy 11.0.2 runs `--mode dns@PORT` next to the regular proxy and listens on UDP and TCP. In
reverse DNS mode with a dead upstream, TCP queries got no reply, most likely because the reverse layer opens the
upstream connection eagerly. In plain DNS mode with the built-in `DnsResolver` removed in `load()`, UDP and TCP both
work, an unanswered query gets `SERVFAIL` from the layer, and `NXDOMAIN` takes 6 ms.

**Observation:** `EnsureCLIAgentRuntimeFiles` writes `base.yml` and `agent.<agent>.yml` only when they are missing.
`agentbox up` therefore never carries a managed-layer change to an existing project; only `agentbox init` does.

**Decision:** The sinkhole is a mitmproxy addon in the existing proxy container on port 5353, and the agent's
firewall rewrites port 53 to it with a `nat` DNAT. This needs no compose change, so `agentbox bump` alone rolls it
out. Binding 53 directly through `net.ipv4.ip_unprivileged_port_start=0` was the runner-up and lost only on
rollout. The `dns:` upstream design lost on the fixed-address requirement, which means a declared subnet and
collisions between projects on one host. A sidecar lost on blast radius.

**Decision:** The addon never resolves a name outside its allowed set. The proxy container's own resolver forwards
unknown names upstream, so consulting it for arbitrary names would move the leak rather than close it.

**Learning:** In DNS mode the built-in resolver runs before script addons and would resolve upstream before a script
could refuse. Removing it from the addon manager at load time is the supported way to take over resolution, and the
layer's behaviour with no response and no upstream is the fail-closed guarantee.
