# Execution Log: m18.2 - dns sinkhole

## 2026-09-13 - The shutdown segfault: an upstream teardown crash, worked around with a launcher

Reproduced outside the test harness with a script that spawns `mitmdump` under `-X faulthandler`, waits for the
DNS listener, optionally sends queries, then sends `SIGTERM`. faulthandler reports the crash in a thread with no
Python frame, which is what a crash during interpreter finalization looks like.

**Observation:** The sinkhole is not the cause. Crash counts per variant, `SIGTERM` after a DNS-mode start: a no-op
addon that handled one query, 4 of 15; the same addon never queried, 0 of 10; an addon that only removes the
built-in resolver, 1 of 6; the real enforcer, 0 of 15 in the script, though it crashed in the suite; the regular
HTTP mode alone, never. Letting the UDP flow time out (20 s) before `SIGTERM` gave 0 of 4. So the trigger is a DNS
flow handled through `mitmproxy_rs`'s Rust UDP server that is still open at shutdown.

**Observation:** `gc.collect()` in the `done()` hook changes nothing (3 of 15). `os._exit(0)` at the end of
`done()` gives 0 of 15, which places the crash after mitmproxy's own shutdown, including every addon's `done()`,
in `Py_Finalize`. Neither the mitmproxy nor the mitmproxy_rs changelog after 11.0.2 / 0.10.7 mentions a fix.
PyPI is blocked from the sandbox, so a newer version could not be tried here.

**Decision:** `images/proxy/run-mitmdump` calls `mitmproxy.tools.main.mitmdump()` and then leaves with `os._exit`
carrying the status mitmdump asked for, so a `sys.exit(1)` from an options error or a startup error is preserved;
checked with `--options` (0) and `--set http2=maybe` (1). Placing the exit in an addon's `done()` was rejected:
`done()` runs inside a `finally` on the `SystemExit` path, so it cannot know the pending status, and built-in addons
later in the chain would lose their `done()`. The entrypoint runs the launcher; the harness spawns it with
`sys.executable`, records the exit status, and `terminate()` raises on anything but 0. A new integration test
spawns, queries over UDP and TCP, and terminates three times. Launcher under the worst variants: 30 of 30 clean.
With the launcher swapped back for plain `mitmdump`, the test caught the crash in 2 of 3 rounds.

**Issue:** Found on the way: CI runs the proxy suite on `pull_request` only, so this branch has never been tested
there, and the workflow installs `mitmproxy` unpinned, which is 12.2.3 today, while the dev venv has 11.0.2.
mitmproxy 12 renamed `dns.Message` to `dns.DNSMessage`; the unit test now takes whichever exists. The proxy image
is `FROM mitmproxy/mitmproxy:latest`, also unpinned. Pinning all three to one version is a separate change.

## 2026-09-13 - Devcontainer run clean; acceptance verified from the sandbox

The maintainer ran `agentbox init --mode devcontainer` on the CLI layout, reopened the repo in VS Code, and ran the
audit with `--container agent-sandbox-devcontainer-agent-1`. Every compared row matches, the VM capture was live
with zero packets carrying the label, and the `iptables -S` dump is identical to the CLI run modulo the network's
addresses (`172.27.0.0/16` against `172.22.0.0/16`). The devcontainer stack is its own compose project, so it ran
beside the CLI stack. Raw run under `results/after-m18.2-20260913-162638/` as a working file.

**Observation:** From the rebuilt CLI sandbox, an allowed URL returns 200 through the proxy and `https://example.com`
gets `CONNECT` 403. Re-running `sudo /usr/local/bin/init-firewall.sh` in place rebuilt the rules and passed all
four self-tests in 0.1 s; `proxy` still resolves and the proxy still answers afterwards. `go test ./...` is green
and the proxy suite runs 224 tests OK.

**Issue:** The proxy suite leaves a 64 MB `core` at the repo root: `mitmdump` dies with `SIGSEGV` (`SEGV_ACCERR`)
when the harness sends `SIGTERM`. Scoped by running the suites apart: only the DNS sinkhole integration tests
produce it, the other integration tests do not, and a plain `mitmdump --mode regular@P --mode dns@P` without the
addon exits 0 on `SIGTERM`. The suite itself passes. Recorded as a follow-up in the task plan; the dump is deleted
and not committed.

**Decision:** The acceptance list is filled in with evidence per criterion. One box stays open: the self-test's
failing direction was verified by reading the script and by the earlier function-level check, not by starting an
agent against a proxy image without the sinkhole. That check needs the Mac and is written up for the maintainer.

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
