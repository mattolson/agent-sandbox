# Task: m18.5 - docs, tests, and agent guidance

## Summary

Document the new boundary, wire the probes into the test suites, and tell agents what changed.

## Scope

From the milestone plan, widened by the follow-ups `m18.2` through `m18.4` handed forward:

- `docs/policy/schema.md`: state that DNS is not policy-controlled and why, and what else the policy does not decide:
  the address guard refuses private answers whatever the policy allows, and IPv6 is denied
- `docs/troubleshooting.md`: entries for every new failure mode, each diagnosable from the entry alone:
  - a tool that resolves names itself gets `NXDOMAIN`
  - a request refused by the address guard (403, `agent-sandbox address guard:`)
  - the agent refuses to start because the DNS sinkhole check failed (proxy image too old)
  - the agent refuses to start because IPv6 is present and `ip6tables` is missing
  - every lookup fails after the proxy container was recreated with a new address
  - the existing "Request blocked unexpectedly" entry gains the guard's event
- The threat in `docs/`: what DNS exfiltration is, what the sandbox does about it, and the residual cases
- The image-baked `operating-in-agent-sandbox` skill: `NXDOMAIN`, the guard's 403, and a quick check that still
  proves what it claims
- `README.md`: the network section and the security principles describe four layers, not two
- Coverage: every control has automated coverage or a documented manual procedure, and the split is written down.
  The probes that fit automated tests were folded in by `m18.2` through `m18.4`; this task writes the split
- Decision records, following the numbering in `docs/plan/decisions/`
- The residuals the tasks recorded: DoH to an allowed host (D2), the proxy container's own resolution, the guard
  trusting the proxy's resolver, and compose sidecars as trusted egress (from the #204 review)
- Operator knobs and paths the tasks deferred to here: `AGENTBOX_DNS_ALLOW`, `NO_PROXY` for sidecars reached through
  the proxy, the repair path after a proxy recreation, and the version-skew behaviour
- Out of scope: any code change to the controls; the stale checked-in `.agent-sandbox/` tree; a name-scoped guard
  exemption, which waits for a user report

## Acceptance Criteria

- [ ] A user who hits the new failure mode can diagnose it from the troubleshooting entry alone
- [ ] The decision record states the alternatives considered and why a policy-driven resolver was rejected
- [ ] Every control in this milestone has either automated coverage or a documented manual procedure, and the split is
      explicit
- [ ] No doc still describes container DNS as unrestricted

## Applicable Learnings

- User-facing docs that quote log shapes must be checked against the emit sites, not paraphrased (m15). The
  troubleshooting entries quote the sinkhole's `dns` events, the guard's `address_guard` events, the 403 bodies, and
  the firewall banner lines; each gets checked against `dns_sinkhole.py`, `address_guard.py`, `enforcer.py`, and
  `init-firewall.sh`
- Keep one canonical doc and link to it rather than re-deriving the same facts in several places (m15). One network
  doc holds the boundary; the README, the schema doc, and troubleshooting link to it
- A skill's quick check must target something the policy actually allows, or it teaches the opposite of the truth
  (m17.4). The current quick check now fails at the sinkhole, not the firewall, and the skill says firewall
- `NXDOMAIN` for an unexpected name is a new and unfamiliar failure mode; without the skill note and the
  troubleshooting entry, agents burn turns misdiagnosing it (milestone risk)
- Don't overclaim. The honest framing, from the milestone: this closes a channel that exists regardless of policy; it
  does not reduce what an allowed host can carry. DoH to an allowed host stays open, and the docs say so
- Measured facts beat documented ones. The tool inventory still marks Node `fetch`, `uv`, `cargo`, and `rustup` as
  "verify"; a troubleshooting entry that tells users which tools need proxy configuration should not rest on that
- A schema-doc change for behaviour that has not shipped is a doc fix, not a migration (m17.5). None of this needs
  `docs/upgrades/`; the changelog already carries the "requires rebuilt images" notes

## Plan

### Files Involved

- `docs/network.md` (new): the network boundary in one place, including the threat section
- `README.md`: the "Network policy" section and the security principles; a link to `docs/network.md`
- `docs/policy/schema.md`: a "What the policy does not control" section
- `docs/troubleshooting.md`: five new entries and the guard event in "Request blocked unexpectedly"
- `images/base/skills/operating-in-agent-sandbox/SKILL.md`: the network model, the quick check, and the blocked-request
  steps
- `docs/plan/decisions/009-dns-sinkhole-in-the-proxy.md` and `010-address-guard-checks-the-dial.md` (new), subject to
  open question 2
- `docs/plan/milestones/m18-dns-egress-controls/bypass-matrix.md`: a "Coverage" section and the resolved pending list
- `docs/roadmap.md`: `m18` marked done when the milestone closes
- `docs/plan/milestones/m18-dns-egress-controls/milestone.md`: the close

No code change. The skill is baked into the base image, so its change reaches users with the next image build.

### Approach

**One network doc.** `docs/network.md` describes the boundary as it now stands, in the order a request meets it:

1. Firewall: direct outbound refused; only the compose network is reachable; IPv6 denied except `::1`
2. DNS sinkhole: the agent resolves only compose service names (`proxy` plus `AGENTBOX_DNS_ALLOW`); every other name
   gets `NXDOMAIN` at once. Proxy-aware tools never notice, because the proxy resolves on their behalf
3. Proxy policy: allowed hosts and request rules, 403 with `Blocked by proxy policy`
4. Address guard: an allowed name that resolves to loopback, private, link-local, metadata, or other non-public
   addresses is refused before the dial, 403 with `agent-sandbox address guard:`; IP-literal hosts are exempt

Then: what each failure looks like from inside the container; a short threat section (DNS exfiltration, what the
sandbox does, the residuals); the operator knobs (`AGENTBOX_DNS_ALLOW`, `NO_PROXY` for sidecars); the repair path
after a proxy recreation; version skew; and how to verify with the audit under `scripts/dns-egress-audit/`. The README
keeps a short version of the four layers and links here, and the schema doc and troubleshooting link here for the
detail.

**Schema doc.** A short "What the policy does not control" section: there is no `dns:` key because names are derived
from the compose stack, not authored, and the proxy resolves allowed hosts itself so the agent never needs to;
`AGENTBOX_DNS_ALLOW` is a proxy environment variable for service names, not policy; the guard applies whatever the
policy allows, except to IP-literal hosts; IPv6 egress is denied.

**Troubleshooting.** Each entry follows the existing shape: the symptom as the user sees it, the cause, how to
confirm it (the exact log line or banner text, checked against the code), and the fix. The `NXDOMAIN` entry covers
per-tool proxy settings, including `NODE_USE_ENV_PROXY` for Node's `fetch`, and states only what was measured; see
open question 3.

**Skill.** The network model lists the four layers. The quick check for a direct connection uses an IP literal, as
the firewall self-test does, so it fails at the firewall as the text says; a second line shows that an unlisted name
does not resolve. The blocked-request steps gain two causes: `NXDOMAIN` means route through the proxy and do not
retry, and a 403 naming the address guard means the host resolves somewhere internal and only the human can change
that. Kept short; the skill is read by every agent at startup.

**Decision records.** Proposed as two, because they are separate decisions with separate alternatives:

- 009: the DNS sinkhole lives in the proxy, reached through a port rewrite, with Docker's resolver rejected outright.
  Alternatives: compose `dns:` to a sidecar, a resolver sidecar, a sysctl to bind port 53, and a policy-driven
  resolver, rejected because resolvable names should follow the compose stack and the proxy already resolves allowed
  hosts on the agent's behalf. IPv6 denied outright rather than mirrored, as a consequence. Residuals
- 010: the address guard checks the dial's own lookup through a wrapper on the loop's `getaddrinfo`. Alternatives:
  check-only, rewriting `server.address` (spiked, breaks tunnels), staging checked answers (built, replaced after the
  #204 review), check-then-verify the peer. Why 403, why IP literals are exempt, why no operator hatch yet, the
  monkeypatch and the invariant tests that gate it. Residuals

**Coverage.** A table in the bypass matrix, one row per control, naming its automated tests (proxy unit and
integration tests, the firewall self-test at every start) and its manual procedure (the audit stage and flags), so
the split is explicit. Controls that only a host can prove, such as H1's "no query left the VM", say so.

**Tool inventory.** See open question 3.

### Implementation Steps

- [ ] Write `docs/network.md`
- [ ] Update the README's network section and security principles
- [ ] Add the schema doc section
- [ ] Add the troubleshooting entries, each checked against the code that emits what it quotes
- [ ] Update the skill
- [ ] Write the decision records
- [ ] Write the coverage table and resolve the matrix's pending list
- [ ] Settle the tool inventory per open question 3
- [ ] Verify each acceptance criterion; mark `m18` done in the roadmap and close the milestone

### Open Questions

1. A new `docs/network.md`, or spread the content across the README and troubleshooting. Recommendation: the new doc.
   The boundary now has four layers, operator knobs, a repair path, and residuals; one canonical place keeps the
   README short and stops the facts drifting apart
2. Two decision records (009 sinkhole, 010 address guard) or one for the milestone. Recommendation: two. They were
   separate decisions with separate alternatives, and 010 carries the monkeypatch rationale a future mitmproxy bump
   will need to find
3. The tool inventory's "verify" entries (Node `fetch` and `undici` per agent, `uv`, `cargo`, `rustup`). Options:
   measure them before the `NXDOMAIN` entry is written, which needs the node-based agent images and the python and
   rust stacks, so it is a host step; or write the entry from documentation and label those tools as unverified.
   Recommendation: measure. I can write a small script that runs one request per tool through the sandbox and
   reports whether it went through the proxy, for you to run in each image
4. `m18.2`'s open acceptance box, the DNS self-test's failing direction, never observed as a real container start.
   Options: close it here with a host step (pin the proxy to a pre-sinkhole image, `agentbox up`, expect the banner),
   or leave it recorded as deferred. Recommendation: close it; it is one `agentbox up`, and the troubleshooting entry
   for that failure quotes the banner it would show
5. m18.5 lands in PR #204, which then leaves draft. Recommendation: yes; the PR description already says it stays a
   draft until m18.5

## Outcome

### Acceptance Verification

_Pending._

### Learnings

_Pending._

### Follow-up Items

_Pending._
