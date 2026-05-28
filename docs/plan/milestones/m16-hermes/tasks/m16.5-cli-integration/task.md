# Task: m16.5 - Hermes CLI Agent Registry Entry

## Summary

Add `"hermes"` to `supportedAgents` in `internal/runtime/agents.go` and update the existing
`TestSupportedAgentsOrder` assertion in `agents_test.go`. This is the unblock that makes `agentbox init --agent hermes`,
`agentbox switch --agent hermes`, `agentbox edit --agent hermes`, and every other agent-aware CLI surface accept the
new agent name.

## Scope

**Included:**
- One-line edit to `internal/runtime/agents.go`: append `"hermes"` to the `supportedAgents` slice.
- One-line edit to `internal/runtime/agents_test.go`: append `,hermes` to the expected order string in
  `TestSupportedAgentsOrder`.
- Smoke verification: build the binary (`go build ./cmd/agentbox`) and run `./agentbox switch --help` to confirm
  `hermes` appears in the agent flag help text. Optionally exercise `./agentbox init --agent hermes --mode cli`
  against a temp directory to confirm the end-to-end init flow works.
- Full Go test suite passes.

**Explicitly out of scope:**
- New tests beyond the existing `TestSupportedAgentsOrder` and `TestValidateAgent`. Every other CLI surface
  (`switch.go`, `edit.go`, `init.go`, `bump.go`, `lifecycle.go`, `legacy.go`) consumes the agent list via
  `SupportedAgents()` / `SupportedAgentsDisplay()`, not by hardcoding names — they pick up hermes for free.
- The `images/build.sh` change to build `agent-sandbox-hermes` and the CI build-images job. Those are m16.6.
- `docs/agents/hermes.md` and README support-matrix updates — m16.7.
- Manual restart-persistence verification — m16.7.

## Acceptance Criteria

- [ ] `internal/runtime/agents.go`'s `supportedAgents` includes `"hermes"`.
- [ ] `internal/runtime/agents_test.go`'s `TestSupportedAgentsOrder` expected string ends with `,hermes` and the test
      passes.
- [ ] `go test ./...` passes.
- [ ] `go vet ./...` clean.
- [ ] Built binary's `agentbox switch --help` and `agentbox init --help` mention `hermes` in the `--agent` flag
      description.
- [ ] `agentbox init --agent hermes --mode cli --project hermes-smoke --path /tmp/hermes-init-smoke` succeeds in a
      throwaway directory (or the equivalent dry-run / template-only invocation that doesn't require Docker images).

## Applicable Learnings

- **List ordering.** Existing `supportedAgents` is not strictly alphabetical; it appears to be "alphabetical batches
  appended as new agents land." Newest agent goes at the end. For hermes that means
  `..., copilot, factory, hermes`. Updating `TestSupportedAgentsOrder` in lockstep is mandatory — the test does an
  exact-string comparison on the joined slice.
- **Other CLI surfaces don't need touching.** All command files (`switch.go`, `edit.go`, `init.go`, `bump.go`) read
  the agent list via `runtime.SupportedAgents()` / `SupportedAgentsDisplay()`. They pick up new agents automatically
  on the next build.
- **Templates and Dockerfile must already exist** (m16.2 and m16.4 — done). Otherwise the init flow accepts the
  agent name but fails to resolve the template or pull the image. Both are in place.

## Plan

### Files Involved

To modify:
- `internal/runtime/agents.go` (one line)
- `internal/runtime/agents_test.go` (one line)

### Approach

1. Append `"hermes"` to `supportedAgents` in `agents.go`.
2. Append `,hermes` to the expected string in `TestSupportedAgentsOrder`.
3. Run `go test ./...` to confirm green.
4. `go build ./cmd/agentbox` to confirm the binary builds.
5. Run `./agentbox switch --help` and `./agentbox init --help` to eyeball that hermes appears in the agent flag help.
6. (Optional but recommended) Exercise `agentbox init --agent hermes --mode cli` against a temp directory to confirm
   templates resolve. Will produce files locally; clean up after.

### Implementation Steps

- [ ] Edit `internal/runtime/agents.go` to add `"hermes"` at the end of `supportedAgents`.
- [ ] Edit `internal/runtime/agents_test.go` to update the expected order string.
- [ ] Run `go test ./...`.
- [ ] Run `go vet ./...`.
- [ ] Build the binary and check `--help` output for both `init` and `switch`.
- [ ] Smoke-run `agentbox init --agent hermes --mode cli --project hermes-smoke --path /tmp/hermes-init-smoke` against
      a temp directory; confirm files are generated without error; clean up the temp directory.

### Open Questions

None substantive. The pattern is established (m11-pi, m12-opencode followed the same one-line edit pattern).

## Outcome

Completed 2026-05-27. Registry entry + three test updates (two more than the plan anticipated; see execution log).

### Acceptance Verification

- [x] `agents.go` `supportedAgents` includes `"hermes"`
- [x] `agents_test.go` `TestSupportedAgentsOrder` expected string ends with `,hermes` and passes
- [x] `init_test.go` and `switch_test.go` expected-error strings updated to include `hermes`
- [x] `go test ./...` passes
- [x] `go vet ./...` clean
- [x] Binary's `agentbox init --help` and `agentbox switch --help` show hermes in the `--agent` flag description
- [-] `agentbox init --agent hermes --mode cli` end-to-end smoke — deferred to m16.7 manual verification on host
      (this sandbox lacks a docker daemon and ghcr.io access; init flow can't resolve the proxy image)

### Learnings

Appended to `docs/plan/learnings.md`:

- When extending an agent/option list that gets rendered into a user-facing error message, grep for the
  joined-list string (e.g., `"claude codex gemini"`) — not just for individual list-member names — because
  tests assert against the literal error string. Tests for the *invalid* case are easy to miss otherwise.

### Follow-up Items

- **m16.7** picks up the host-side end-to-end smoke: `agentbox init --agent hermes --mode cli` followed by
  `agentbox up` and a real interactive Hermes session, including restart-persistence of `HERMES_HOME`.
- **m16.6** still needs to wire hermes into `images/build.sh` (build job) and CI (build-images.yml +
  check-hermes-version.yml). Without those, the agent image isn't published to ghcr, so end-users running
  `agentbox init --agent hermes` would hit the same "no local copy exists" failure m16.5's smoke hit.
