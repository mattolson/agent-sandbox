# Task: m18.6 - firewall CI tests

## Summary

Run the agent firewall and the DNS sinkhole end to end in CI, with IPv6 on and off, so this repo's dev sandbox no longer
has to keep IPv6 enabled to exercise the IPv6 path.

## Scope

A follow-up to the milestone, opened on 2026-09-28 after it closed:

- A GitHub Actions workflow that builds the base and proxy images from the PR, starts a two-service stack (the proxy,
  and an agent running the bare base image), and checks the result, once with IPv6 enabled on the compose network and
  once with it off
- Checks: the firewall's startup output (the `PASS` lines, `IPv6: present` or `absent`), and the in-container audit
  rows through `run-audit.bash`
- The fail-closed start without `ip6tables`, coverage procedure 1, automated in the IPv6-on run
- Once the workflow passes on `main`'s side of the stack, turn IPv6 off in this repo's `user.override.yml` and update
  the lines that say the repo keeps it on
- One change to the controls, approved 2026-09-30: a fifth startup check in `init-firewall.sh`, a raw query to
  Docker's resolver at `127.0.0.11` that must be rejected, after the deliberate-failure run showed no startup check
  covered that rule
- Out of scope: the host-only rows (H1, the VM capture, and H2), which need Colima; any other change to the controls

## Acceptance Criteria

- [x] A PR that touches `images/base/`, `images/proxy/`, or the audit scripts runs the workflow. It ran on every push
      to #204 from 2026-10-01
- [x] With IPv6 on, the run fails if any IPv6 self-test line is missing, any E row does not read `rejected`, or the
      firewall starts without `ip6tables`. The driver checks each; passing in CI on Docker 28.0.4 and locally on 29.2.1
- [x] With IPv6 off, the run fails if the `absent` line is missing or any IPv4 or DNS row regresses. Seen failing on a
      firewall without its resolver rule, first in the audit rows and then at start
- [x] The workflow was seen to fail on a deliberately broken firewall before it is trusted. Locally, 2026-09-30, the
      same script CI runs
- [x] This repo's dev sandbox runs with IPv6 off, and no doc still says the repo keeps it on. The maintainer removed
      the override on 2026-10-01; the start banner reads `IPv6: absent on eth0`, and the audit README, the m18.3
      decision, and the m18.3 task now say so

## Applicable Learnings

- An empty capture is not evidence of absence, and a test only guards an invariant if its code path runs through the
  thing it guards (m18.3, m18.4). The workflow has to be seen to fail on a broken firewall, not just to pass
- Check which artifact a test actually ran (m18.5). The workflow builds the images from the PR, and each run records
  the image it tested
- Pushes whose commits change `.github/workflows/` need the `workflow` scope, which the sandbox token lacks; the
  maintainer pushes this branch from the host (`AGENTS.md`)
- An audit that skips expected rows now exits 2 (m18.4 review). Rows the CI cannot run, such as H1, must be marked `*`
  in the CI expectation files, not left to skip
- The base image's entrypoint needs only a service named `proxy` that serves the sinkhole; the CA install is skipped
  when no CA is mounted. The proxy renders its baked default policy when given no policy files

## Plan

### Files Involved

- `.github/workflows/firewall-tests.yml` (new)
- `images/base/tests/compose.firewall-test.yml` (new, or under `scripts/dns-egress-audit/`; see open question 2): the
  two-service stack, with the IPv6 setting supplied per run
- `scripts/dns-egress-audit/expected/ci-ipv6-on.tsv` and `ci-ipv6-off.tsv` (new): the in-container rows, with host-only
  rows marked `*`
- `scripts/dns-egress-audit/run-audit.bash`: only if running without `agentbox` or Colima needs a change
- `.agent-sandbox/compose/user.override.yml`: remove `enable_ipv6`, at the end
- `scripts/dns-egress-audit/README.md`, the m18.3 decision in `milestone.md`, and `docs/plan/decisions/009-*`: the "keeps
  it on" lines

### Approach

**Spike first.** A throwaway workflow run that prints the runner's Docker Engine and Compose versions, creates an IPv6
network, and starts one container on it. Whether the runner's Docker assigns an IPv6 prefix without a declared subnet
is unknown; in CI a fixed unique-local subnet is fine, because nothing else shares the runner.

**The stack.** The proxy image with `cap_drop: ALL` and its health check, and an agent service on the base image with
the firewall's capabilities, `HTTP_PROXY` and `HTTPS_PROXY` pointing at `proxy:8080`, and `depends_on` the proxy being
healthy. No policy mounts and no secrets. IPv6 on or off per run through the network definition.

**The checks.** Wait for the agent to finish its firewall start, then:

- grep its log for each expected line and for no `FAIL` or `ERROR`
- run `run-audit.bash --container <agent> --stage ci-ipv6-on|off --skip-vm`, which runs the in-container probes and a
  peer responder on the compose network, and exits non-zero on a mismatch or a skipped expected row
- in the IPv6-on run, move `ip6tables` aside as root, re-run the firewall, and expect exit 1 and the error line

**Trusting it.** Before relying on the workflow, break the firewall on a scratch commit, for example by dropping the
IPv6 reject rule, and see the run fail. Record the failing run in the log.

**Then turn IPv6 off.** Remove the override block, update the docs that say the repo keeps it on, and record the
change in the milestone.

### Implementation Steps

- [x] Spike the runner's IPv6 support: folded into the workflow, which prints the engine version and declares a
      subnet on engines before 27; the first CI run was the spike
- [x] Write the compose stack and the two expectation files
- [x] Write the workflow; maintainer pushes the branch from the host
- [x] See the test fail on a deliberately broken firewall, then pass on the real one (locally, 2026-09-30)
- [x] Turn IPv6 off in this repo's dev sandbox and update the docs
- [x] Verify each acceptance criterion and capture learnings

### Open Questions

All five resolved 2026-09-30 as recommended: the bare base image as the agent; the stack under `images/base/tests/`;
a hand-written compose file; the `proxy-tests.yml` trigger paths; stacked on #204. Changed later that day: folded
into #204 instead, by fast-forwarding its branch, so the end-to-end test gates the firewall changes it tests and no
rebase or force-push is needed after #204 merges.

6. Resolved 2026-09-30: yes, added. Raised by the deliberate-failure run. The firewall's startup checks passed with the `127.0.0.11` reject
   rule deleted, because none of them tests Docker's resolver. Add a fifth check, a raw DNS query to `127.0.0.11` on
   port 53 that must read `rejected`, so every container start catches that regression rather than only this test or
   a host audit. Recommendation: yes; it reuses `dns_rcode`, which already reports `rejected`, and costs one send

## Outcome

### Acceptance Verification

All five criteria are ticked above. The workflow runs on every relevant push to #204 and passed on Docker Engine 28.0.4,
Ubuntu amd64; the same script passes locally on Colima arm64, Docker 29.2.1; and it was seen to fail on a firewall
missing its rule against Docker's resolver.

### Learnings

- A deliberate-failure run is worth doing even when the test looks complete. Deleting one firewall rule showed that
  none of the firewall's own startup checks covered it, which led to the fifth check
- A CI runner is a different host, not a faster laptop. Docker's upstream there is systemd-resolved's loopback, which
  broke an audit assumption that held on Colima for the whole milestone
- When the sandbox cannot read a system's output, make the system report through a channel it can read. GitHub
  annotations come from `api.github.com`; job logs and artifacts do not
- Under `set -e`, a test driver needs an ERR trap that reports, or the most basic failures, such as a Compose error,
  end the run with nothing to diagnose
- Fixed container and project names make concurrent test runs collide; name them per run

### Follow-up Items

- None for the milestone. The host-only rows, H1 and H2, stay manual by nature
