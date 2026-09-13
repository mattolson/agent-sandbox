# Execution Log: m18.2 - dns sinkhole

## 2026-09-12 - Proxy addon, firewall rewrite, tests, and audit rows landed; host run pending

Approved as planned. The branch was renamed to `m18-dns-egress-controls` for the whole milestone first.

**Decision:** `dns_sinkhole.py` keeps its decision logic in a pure `classify()` function over integers, so the
unit tests cover every branch without building mitmproxy objects, and a second set drives `dns_request` with real
`dns.Message` instances and a fake resolver. `enforcer.py` registers the addon in `build_addons()` with its own
`JsonLogger`, so one `-s` flag loads both and the Dockerfile only gains the two `--mode` flags.

**Decision:** The allowlist always contains `proxy`; `AGENTBOX_DNS_ALLOW` extends it and rejects anything that is
not an exact host name. Answers are not logged, refusals are, as `{"type": "dns", "action": "nxdomain", ...}`
with the client address.

**Observation:** The integration harness needed a `dns=True` switch that lists both modes explicitly, because any
`--mode` replaces mitmproxy's default regular mode. Six integration tests against the real `mitmdump` pass: UDP
and TCP refusals, an allowed name answered on both transports with the 30 second TTL, empty `NOERROR` for TXT, the
HTTP allowlist not leaking into DNS, HTTP enforcement unaffected, and the listening event confirming the built-in
resolver was removed. The full proxy suite is 224 tests, all green.

**Decision:** `init-firewall.sh` carries a small bash DNS client, `dns_rcode`, so the negative self-test asserts an
actual `NXDOMAIN` from the sinkhole through the port-53 rewrite, and can tell a refusal from a forward, a hang, or
a rejected send. `getent` alone could not distinguish `NXDOMAIN` from `SERVFAIL`. Exercised against the live
embedded resolver: `0` for a public name, `3` for a `.invalid` name, `timeout` for a dead port, `rejected` for a
blocked address.

**Decision:** The negative connect test now targets `https://1.1.1.1`. A hostname would fail at resolution and
prove nothing about the firewall.

**Observation:** S1 through S3 measured from this sandbox before the change all read `timeout`: the proxy container
has no listener on 53 or 5353 today and answers with no ICMP error. Recorded in the matrix as the baseline for the
control rows.

**Issue:** `go test ./...` is unaffected in principle since nothing under `internal/` changed; run anyway to be sure.

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
