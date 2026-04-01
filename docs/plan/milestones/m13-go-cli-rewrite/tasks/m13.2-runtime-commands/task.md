# Task: m13.2 - Runtime Commands

## Summary

Port the commands that primarily discover the active runtime and shell out to Docker/Compose, giving the Go CLI real end-to-end behavior early.

## Scope

- Port `compose`, `up`, `down`, `logs`, `exec`, `policy config`, `policy render`, and `version`
- Recreate layered compose discovery and legacy-layout guardrails
- Preserve passthrough argument handling, TTY behavior, and environment propagation expected by the current CLI
- Keep `policy config` on the existing proxy-driven render path (`docker compose run ... render-policy`) rather than duplicating merge logic in Go

## Acceptance Criteria

- [ ] The Go CLI resolves the same effective compose stack as the Bash CLI for representative CLI-mode and devcontainer fixtures
- [ ] Docker/Compose commands invoked by the Go implementation match the current semantics for passthrough and runtime targeting
- [ ] `agentbox policy config` still renders through the proxy helper and returns the effective policy
- [ ] Legacy single-file layouts fail fast with guidance equivalent to the current UX

## Applicable Learnings

- Keep `.agent-sandbox/` as the clear ownership boundary for generated runtime files and user-owned overrides; the Go rewrite should preserve that contract rather than redesign it.
- Devcontainer mode should remain a thin IDE-facing shim over the centralized `.agent-sandbox/` runtime files, not become a second source of truth.
- Strong ownership boundaries are safer than patching arbitrary user-edited YAML in place, so runtime resolution should clearly separate managed compose layers from user-owned overrides.
- Security-sensitive policy rendering should keep one merge path. `agentbox policy config` should continue to invoke the proxy helper rather than introducing a host-side policy merge implementation.
- Relative paths in Docker Compose files are resolved from the compose file's directory, not the project root, so emitted compose file order and paths need to match the current layered layout exactly.
- Legacy-layout guardrails belong in user-facing entrypoints rather than low-level helpers so unsupported single-file projects fail with actionable upgrade guidance.
- The existing Bash CLI behavior and tests are the best available spec, so `cli/lib/run-compose`, `cli/libexec/exec/exec`, `cli/libexec/policy/config`, and the current BATS coverage should drive the Go port.

## Plan

### Files Involved

- `internal/cli/root.go` - replace pending runtime command placeholders with real command wiring
- `internal/cli/runtime_commands.go` - shared command constructors for `compose`, `up`, `down`, `logs`, and `exec`
- `internal/cli/policy.go` - `policy config` and `policy render` command behavior
- `internal/cli/version.go` - keep `version` aligned with the shared runtime command wiring style if minor adjustments are needed
- `internal/runtime/compose.go` - emit compose file lists in the same order as the Bash CLI and decide when runtime sync is required
- `internal/runtime/legacy.go` - detect unsupported legacy layouts and render upgrade guidance equivalent to the Bash UX
- `internal/docker/invocation.go` - extend subprocess helpers for streaming execution, command capture, and testable runners
- `internal/testutil/*.go` - temp repo, fake runner, and command execution helpers reused across runtime command tests
- `internal/cli/*_test.go` - command-level tests for passthrough args, exec behavior, and policy aliasing
- `internal/runtime/*_test.go` - fixture-based tests for compose file resolution and legacy-layout failures
- `docs/plan/milestones/m13-go-cli-rewrite/tasks/m13.2-runtime-commands/*.md` - living task plan and execution log

### Approach

Port the runtime entrypoints around reusable runtime and docker packages instead of putting behavior directly inside Cobra handlers. `compose`, `up`, `down`, and `logs` should share a single runtime-command path that resolves the repo root, checks for unsupported legacy single-file layouts, chooses layered CLI versus centralized devcontainer mode, emits the correct ordered compose file list, and then execs `docker compose` with passthrough arguments unchanged. The only per-command difference should be the default compose subcommand prefix (`up`, `down`, `logs`, or none for `compose`) and the user-facing command name used in errors.

Keep `policy config` on the existing proxy-side render path. In Go that should still resolve the same compose stack as `run-compose`, skip runtime sync for the render helper invocation, and run `docker compose ... run --rm --no-deps -T --entrypoint /usr/local/bin/render-policy proxy`, capturing stdout so the effective policy is returned exactly as the helper prints it. `policy render` should remain an alias for `policy config`, and `version` should stay as the already-ported build-info command from m13.1.

Treat `exec` as a thin orchestration wrapper over the shared compose runner. It should first check `docker compose ... ps agent --status running --quiet`; if the agent container is not running, it should start the stack with `up -d`; then it should exec into the `agent` service with the default shell `zsh` or the user-supplied command. The subprocess layer should support both streamed TTY passthrough for normal runtime commands and captured output for checks like `ps` and `policy config`.

The main boundary call for m13.2 is runtime sync. The Bash CLI refreshes certain managed runtime files before mutating compose commands. My recommendation is to port the decision points now and add a narrow Go runtime-sync hook only if it is needed to preserve current runtime-command semantics for already-initialized projects. If matching the Bash refresh path would force a large amount of YAML or scaffold-generation logic into this task, stop short of a full rewrite and keep the plan focused on layout resolution, guardrails, and Docker/Compose invocation; the deeper scaffold port belongs in m13.3.

Testing should mirror the current Bash BATS coverage rather than inventing new behavior. Add Go tests that assert the ordered compose file list for layered CLI and centralized devcontainer fixtures, the mutating-command runtime-sync predicate, the `exec` startup behavior, the exact `policy config` docker invocation, and the legacy-layout error message shape. Keep the Bash CLI and its tests untouched; the Go tests should prove parity for the newly ported behavior without cutting over the distribution path.

### Implementation Steps

- [x] Add runtime layout and compose file resolution helpers in `internal/runtime` with focused fixture-based tests for layered CLI, centralized devcontainer, and missing-layout cases
- [x] Add legacy-layout detection plus user-facing upgrade guidance in Go, matching the current runtime command failure semantics closely enough for existing upgrade docs to remain correct
- [x] Extend the docker subprocess layer to support streamed exec and captured output so runtime commands, `exec`, and `policy config` can share one implementation style
- [x] Port `compose`, `up`, `down`, `logs`, `exec`, `policy config`, and `policy render` onto real Cobra handlers using the shared runtime and docker packages
- [x] Decide whether a narrow runtime-sync hook is required for mutating commands in m13.2; implement it only if needed to preserve current runtime-command behavior without dragging full init/scaffolding work into this task
- [x] Add Go tests for runtime command argument passthrough, compose file order, `exec` startup behavior, `policy config`/`policy render`, and legacy-layout errors
- [x] Verify `go test ./...`, `go build ./cmd/agentbox`, and representative `go run ./cmd/agentbox ...` runtime command paths with a stubbed or real Docker environment as appropriate

### Open Questions

None after execution. The command port kept the runtime-sync seam injectable, and the current parity coverage did not require pulling the broader Bash refresh path forward into m13.2.

## Outcome

### Acceptance Verification

- [x] The Go CLI resolves the same effective compose stack as the Bash CLI for representative CLI-mode and devcontainer fixtures via `internal/runtime/compose_test.go` and `internal/cli/runtime_commands_test.go`.
- [x] Docker/Compose commands invoked by the Go implementation match the current semantics for passthrough and runtime targeting, including `exec` startup behavior, through `internal/cli/runtime_commands_test.go`.
- [x] `agentbox policy config` still renders through the proxy helper path and returns the helper output via `internal/cli/policy_test.go`.
- [x] Legacy single-file layouts fail fast with upgrade guidance equivalent to the current UX via `internal/runtime/legacy_test.go` and `internal/cli/runtime_commands_test.go`.

### Learnings

- A reusable runtime-layout resolver plus an injectable Docker runner makes early Go CLI parity testing straightforward without a live Docker daemon.
- Keeping runtime sync as an explicit seam, but leaving the default implementation minimal, lets the runtime command port stay focused on discovery and subprocess semantics while preserving room for the fuller scaffold refresh work in `m13.3`.

### Follow-up Items

- Revisit the default runtime-sync implementation during `m13.3` if init/scaffolding porting reveals additional managed-file refresh work that `compose up` or `exec` should perform automatically in the Go CLI.
