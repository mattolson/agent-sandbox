# Execution Log: m18.2 - dns sinkhole

## 2026-09-13 - after-m18.2 host run clean in CLI mode

Re-run of `run-audit.bash --stage after-m18.2` after the audit fixes. Every compared row matches. The only
skipped rows are the policy probes D2 through D4, which need the temporary policy entries and `--policy-probes`;
they are not part of this task's acceptance. The raw run is under `results/after-m18.2-20260913-161555/` as a
working file.

**Observation:** The VM capture was live for the whole window: `tcpdump` on `any` reported the run ending on the
`timeout` exit and zero packets carrying the label, so H1's `not-seen` is a measurement, not a capture that failed
to start. The peer log holds one UDP query for `example.com` from `172.22.0.5`; that is the H3 throwaway container
forwarding through its `--dns` setting after the probes ran, not the agent, whose B3 and B4 read `rejected`.

**Observation:** The runner learned the upstream `192.168.5.1` from the throwaway container's `resolv.conf`, and
C1 and C2 read `rejected` against it.

**Issue:** Left for acceptance: the devcontainer run with `--container`, then the criteria checklist.

## 2026-09-12 - First after-m18.2 host run: the firewall held, the audit had two defects

The maintainer rebuilt both images, ran `agentbox up`, and ran `run-audit.bash --stage after-m18.2` in CLI mode.
Three rows mismatched: A8, C1, and C2. Every other compared row matched, including all thirteen flips and H1's
`not-seen` from the VM capture.

**Observation:** A8 read `rejected` against an expected `answered`. A8 is a raw UDP query to `127.0.0.11` for
`proxy`, and rule 3 rejects that address outright, so `rejected` is the designed result; the planning value was
carried over from baseline by mistake. S3, `proxy` A to `proxy:53`, read `answered` and is the service-name
control from here on.

**Decision:** A8 reads `rejected` in the after-m18.2, after-m18.3, and after-m18.4 files and joins the must-differ
list. Pinning A8 to `127.0.0.11` rather than following `resolv.conf` keeps it as evidence that the embedded
resolver is unreachable even for a legitimate name.

**Observation:** C1 and C2 read `error`, `no ExtServers line in resolv.conf`. The probe learned the upstream from
Docker's comment in the agent's `resolv.conf`, which `init-firewall.sh` now rewrites. The upstream did not change:
a throwaway container on the same network still gets `ExtServers: [host(192.168.5.1)]`.

**Decision:** `run-audit.bash` reads the comment from a throwaway `python:3-alpine` container on the sandbox
network, saves it as `network-resolv.conf` in the run directory, and passes `--upstream` to `probe.bash`, which
gains that option and falls back to the old parse. The firewall script stays untouched; preserving Docker's
comment there would have put an audit convenience in a security-critical file. Verified from the rebuilt
sandbox: `probe.bash --only A8,C1,C2 --upstream 192.168.5.1` reads `rejected` for all three.

**Issue:** The host run needs repeating in CLI mode, and the devcontainer run is still pending.

## 2026-09-12 - Rebuilt proxy verified live from the old agent container

The maintainer rebuilt `agent-sandbox-proxy:local` and recreated only the proxy, so the sinkhole could be checked
from the still-running agent container before the agent image changes.

**Observation:** From the agent, `proxy:5353` answers `proxy` A with the proxy's address, empty `NOERROR` for AAAA
and TXT, `NXDOMAIN` for a random label over UDP and over TCP, and `NXDOMAIN` for a 253-byte name. Audit row S2
reads `nxdomain`; S1 and S3 still time out because the port-53 rewrite lives in the agent image that is not yet
rebuilt. The HTTP proxy is unaffected: allowed URLs succeed and an unlisted host still gets the policy 403.

**Observation:** `https://github.com/` through the proxy returns 403 in this repo's sandbox. That is the repo's
path-scoped GitHub policy, which allows only the git and API paths, not a regression; the milestone's acceptance
wording assumes a host-level allow. The check here uses URLs the policy allows.

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
