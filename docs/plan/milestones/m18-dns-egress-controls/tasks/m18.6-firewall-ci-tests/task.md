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
- Out of scope: the host-only rows (H1, the VM capture, and H2), which need Colima; the address guard, which the proxy
  suite already covers in CI; any change to the controls themselves

## Acceptance Criteria

- [ ] A PR that touches `images/base/`, `images/proxy/`, or the audit scripts runs the workflow
- [ ] With IPv6 on, the run fails if any IPv6 self-test line is missing, any E row does not read `rejected`, or the
      firewall starts without `ip6tables`
- [ ] With IPv6 off, the run fails if the `absent` line is missing or any IPv4 or DNS row regresses
- [ ] The workflow was seen to fail on a deliberately broken firewall before it is trusted
- [ ] This repo's dev sandbox runs with IPv6 off, and no doc still says the repo keeps it on

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

- [ ] Spike the runner's IPv6 support
- [ ] Write the compose stack and the two expectation files
- [ ] Write the workflow; maintainer pushes the branch from the host
- [ ] See the workflow fail on a deliberately broken firewall, then pass on the real one
- [ ] Turn IPv6 off in this repo's dev sandbox and update the docs
- [ ] Verify each acceptance criterion and capture learnings

### Open Questions

1. The agent service runs the bare base image rather than an agent image. Recommendation: yes. The firewall and its
   checks live in the base image, and an agent image would add minutes of build for no extra coverage of this path
2. Where the test compose file lives: next to the firewall under `images/base/tests/`, or with the audit under
   `scripts/dns-egress-audit/`. Recommendation: `images/base/tests/`, since it tests the base image, with the
   expectation files staying beside the others
3. Whether to build the stack from `agentbox init` output instead of a hand-written compose file, so the templates are
   tested too. Recommendation: hand-written for now. `agentbox init` pins and may pull the published agent images,
   which is slow and tests a different thing; the Go suite already covers template generation
4. The workflow's trigger: PRs and pushes to `main` that touch `images/base/`, `images/proxy/`,
   `scripts/dns-egress-audit/`, or the workflow itself. Recommendation: yes, matching `proxy-tests.yml`
5. The stacking. This branch starts from `m18-dns-egress-controls` because it needs the m18 code. Its PR merges after
   #204 and is rebased onto `main` when #204 lands. Recommendation: as described

## Outcome

### Acceptance Verification

_Pending._

### Learnings

_Pending._

### Follow-up Items

_Pending._
