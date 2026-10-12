# Execution Log: m18.5 - docs, tests, and agent guidance

## 2026-09-28 - Procedure 1 run; task and milestone closed

**Issue:** The first run of procedure 1 refused to start as expected, but its message was the pre-#204 format: the dev
image's installed `init-firewall.sh` predates b6046b7, so it tested the old check. Running the repo's copy from
`/workspace` tested the fix, first with the global address present and then with it removed, leaving only
`fe80::ec55:d0ff:fe5c:753c/64`. Both refused with exit 1; the old script would have started in the second case. The
container's address, route, and `ip6tables` were restored and the installed firewall re-run cleanly.

**Observation:** `AGENTS.md` still described two enforcement layers and listed neither new addon among the
security-critical files. Updated with the close, since agents working on this repo read it first.

All four acceptance criteria verified. `m18` marked done in the roadmap; out-of-scope findings moved to
`docs/plan/cleanup-tasks.md`.

## 2026-09-28 - Tool inventory measured; version skew observed

**Observation:** `tool-probe.bash` took three runs in a hermes image on the node, python, and rust stacks. The first
two exposed probe faults, not tool behaviour: cargo and rustup live on a PATH only login shells load; uv's wording
was `tunnel error: unsuccessful`, not the guessed pattern; rustup could not write its root-owned `RUSTUP_HOME`; and
with `NODE_USE_ENV_PROXY=1` the real proxy's refusal surfaced only as `Request was cancelled.`. Pointing
`HTTPS_PROXY` at a dead port settled Node: with the flag it failed on `127.0.0.1:9`, without it on the name. Result:
every probed tool uses the proxy except Node 22's built-in `fetch`, which `NODE_USE_ENV_PROXY=1` fixes.

**Observation:** Procedure 2 run. The sinkhole agent image against the proxy image published from `main` stopped
after 30 s with the expected error and `FATAL` banner. That closes `m18.2`'s last open acceptance box, and the
troubleshooting entry now quotes the output as printed.

## 2026-09-28 - Docs written; host checks outstanding

Approved as recommended. Written: `docs/network.md`, the README's four layers, the schema doc's "What The Policy Does
Not Control", five troubleshooting entries, the skill update, decisions 009 and 010, and a coverage table in the
bypass matrix. Every quoted message was taken from the code that emits it.

**Issue:** Two claims were wrong until checked. HTTPS clients never show the guard's body: curl reports
`CONNECT tunnel failed, response 403`, the same as a policy block, so the entry and the network doc now send the
reader to the proxy log. And curl reports an unresolvable proxy as `Could not resolve proxy: proxy`, not
`Could not resolve host`.

**Observation:** Reaching a sidecar by name takes two settings: the name in `AGENTBOX_DNS_ALLOW` on the proxy so it
resolves, and in `NO_PROXY` on the agent so HTTP clients connect directly; through the proxy, the address guard
refuses the sidecar's private address. Missing either gives a different failure, and both entries say so.

**Issue:** The coverage table showed that refusing to start with IPv6 present and no `ip6tables` had neither a test nor
a procedure; the #204 fix was checked only with `bash -n`. Procedure 1 moves the binary aside inside a running agent
and re-runs the firewall. Not yet run.

**Observation:** `tool-probe.bash` classifies each tool by fetching `example.com`: the proxy's 403 means it used the
proxy, a DNS error means it resolved the name itself. Its control row, curl with the proxy off, read `direct-dns` in
the dev sandbox, and curl, git, python `urllib`, pip, and go read `proxied`. The hermes image keeps `uv` at runtime
despite the "build-time only" comment on its install, so a hermes image on the node, python, and rust stacks carries
every unmeasured tool.

## 2026-09-28 - Planning

No user doc mentions DNS, so no doc describes it as unrestricted; the gap is that nothing explains the new
behaviour. The README and the baked `operating-in-agent-sandbox` skill both describe two enforcement layers, and the
skill's quick check, `curl --noproxy '*' https://example.com`, now fails at name resolution while the skill says the
firewall refuses it. An agent following the skill would see `NXDOMAIN` and draw the wrong conclusion.

`m18.2` through `m18.4` handed forward the repair path after a proxy recreation, `AGENTBOX_DNS_ALLOW`, the DoH
residual, the version-skew banner, the IPv6 banner lines, the guard's 403 and event, the IP-literal exemption,
`NO_PROXY` for sidecars, the guard's residuals, sidecars as trusted egress, and the unmeasured tool inventory. All are
in the scope.

**Decision (proposed):** one new `docs/network.md` as the canonical description, two decision records, and a coverage
table in the bypass matrix. Five open questions in `task.md`. Awaiting approval.
