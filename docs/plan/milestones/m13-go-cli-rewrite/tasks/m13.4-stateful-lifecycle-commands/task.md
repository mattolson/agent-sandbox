# Task: m13.4 - Stateful Lifecycle Commands

## Summary

Port the commands that mutate existing initialized projects while preserving user-owned state, restart semantics, and layered ownership boundaries.

## Scope

- Port `switch`, `edit compose`, `edit policy`, and `destroy`
- Preserve active-agent tracking, lazy scaffolding of per-agent runtime files, and devcontainer refresh behavior
- Recreate edit-time change detection, automatic proxy/container restart behavior, and warning paths
- Preserve confirmation/force flows for destructive cleanup

## Acceptance Criteria

- [ ] `agentbox switch` preserves shared and agent-specific overrides while refreshing the selected runtime correctly
- [ ] `agentbox edit compose` and `agentbox edit policy` target the same user-owned files and apply the same restart/warning semantics as today
- [ ] `agentbox destroy` removes layered runtime files and compose resources with the current confirmation behavior
- [ ] Regression coverage exists for legacy-layout failures and same-agent refresh paths

## Applicable Learnings

- Keep `.agent-sandbox/` as the clear ownership boundary for generated runtime files and user-owned overrides; lifecycle commands should refresh managed files around that boundary rather than patching arbitrary user edits.
- Default edit commands should keep pointing at the shared cross-mode config unless the user explicitly asks for a more specific override surface.
- Devcontainer mode should remain a thin IDE-facing shim over the centralized `.agent-sandbox/` runtime files, so switch/edit flows should continue treating the shared compose and policy overrides as the primary user-owned surfaces.
- The runtime-command port already created a reusable compose-stack resolver and runtime-sync seam; `m13.4` should reuse those seams instead of introducing a second path for Docker/Compose invocation.
- The native scaffold generation added in `m13.3` is the right source for recreating missing managed files and policy mounts, but lifecycle refresh must preserve existing pinned images and all user-owned overrides.
- Shell-safe `active-target.env` parsing/writing is already implemented in Go, so switch behavior should preserve existing IDE and project metadata instead of re-deriving it opportunistically.
- This task carries the highest user-data-loss risk in the milestone, so tests should assert preserved override/policy contents and state-write ordering instead of relying only on happy-path command success.

## Plan

### Files Involved

- `internal/cli/root.go` - replace the pending `switch`, `edit`, and `destroy` placeholders with real command wiring
- `internal/cli/switch.go` - flag parsing, optional prompting, same-agent refresh, restart ordering, and user-facing switch messages
- `internal/cli/edit.go` - `edit compose` and `edit policy` command behavior, editor launching, change detection, and restart/warning flows
- `internal/cli/destroy.go` - force/confirmation handling, compose teardown, and filesystem cleanup
- `internal/cli/runtime_commands.go` - optionally replace the default noop runtime syncer once scaffold-backed refresh helpers exist
- `internal/runtime/compose.go` and/or a new `internal/runtime/lifecycle.go` - shared detection for initialized layouts, edit target selection, and destroy-time compose resolution without duplicating command logic
- `internal/runtime/editor.go` - reuse the existing native editor resolution helper, with minor adjustments only if command execution needs more injection points for tests
- `internal/scaffold/init.go` and/or a new `internal/scaffold/sync.go` - reusable `ensure` helpers for layered CLI and centralized devcontainer runtime refresh built on the native scaffold writers from `m13.3`
- `internal/cli/*_test.go` - command-level tests for switch/edit/destroy behavior, restart calls, warnings, and runtime-sync follow-up
- `internal/runtime/*_test.go` / `internal/scaffold/*_test.go` - lower-level tests for preserve-file semantics, state-write ordering, and lifecycle helper decisions
- `docs/plan/milestones/m13-go-cli-rewrite/tasks/m13.4-stateful-lifecycle-commands/*.md` - living task plan and execution log

### Approach

Port the lifecycle commands as thin Cobra handlers over reusable runtime and scaffold helpers instead of translating the Bash entrypoints line by line. The Go CLI already has the core building blocks for repo discovery, legacy-layout errors, compose-stack resolution, editor parsing, active-target state handling, and native scaffold generation. `m13.4` should connect those pieces into one lifecycle path that refreshes only agentbox-managed files, leaves user-owned override and policy files untouched, and keeps user-facing messages and restart behavior aligned with the Bash CLI.

For `switch`, preserve the current ordering and guardrails precisely. Explicit `--agent` values should be validated before any legacy-layout handling. If the project is not initialized, fail with the current `Run 'agentbox init' first.` guidance. If the requested agent is already active, refresh the relevant managed runtime files and return the corresponding `Refreshed layered runtime files.` message instead of rewriting state blindly. If a different agent is selected, detect whether the current runtime is running with the old active agent, scaffold the target agent's managed files before the switch, and write `active-target.env` only after a successful `down` when containers are running so restart uses the old stack for shutdown and the new stack for startup. In centralized devcontainer layouts, preserve the current IDE and project metadata and keep the `persist_state=false` refresh behavior until the switch is committed.

For `edit compose`, keep the default target on the shared compose override file in both layered CLI and centralized devcontainer layouts, scaffolding the shared override file if the layered layout exists but the user-owned file is still missing. Use the native editor helper already in `internal/runtime/editor.go`, capture modification state via file metadata or an equivalent stable content check, and then mirror the current restart behavior: when the file changed and containers are running, either restart with `up -d` or print the no-restart warning depending on `--no-restart` / `AGENTBOX_NO_RESTART`; otherwise print the same no-change or modified-without-running-runtime messages.

For `edit policy`, preserve the current targeting rules rather than inventing new ones. The default target remains the shared layered policy file. `--agent <name>` should scaffold and open that agent's user-owned policy file, but if the selected agent is not currently active the command should warn that changes apply only after `agentbox switch --agent <name>` and skip any proxy restart. `--mode devcontainer` should continue to map to the shared layered policy surface in centralized devcontainer layouts instead of exposing the managed `policy.devcontainer.yaml` file for editing. When the edited policy affects the active runtime and the proxy service is running, restart only `proxy`; otherwise keep the current skip-restart warning.

For `destroy`, keep the current cleanup contract instead of reusing the strict legacy-layout failures used by `switch` and `edit`. The Bash implementation intentionally uses `destroy` as the escape hatch for both layered and legacy single-file projects, so the Go port should first attempt to stop the relevant compose stack with `down --volumes`, warn and continue if shutdown fails, and then remove `.agent-sandbox/` and `.devcontainer/` after either `--force` or an interactive confirmation. This task should preserve the layered cleanup behavior for active Go-managed projects while still allowing legacy users to clean up old layouts without a manual Docker step.

Once the scaffold-backed refresh helpers exist, revisit the noop runtime-sync default added in `m13.2`. If wiring the new refresh helper into `compose up/run/start/restart` and `exec` is the smallest way to recover the existing Bash managed-file refresh semantics, do it here; if not, keep the scope focused on the stateful lifecycle entrypoints and document the remaining gap explicitly. Either way, tests should stay parity-focused: assert compose invocations, restart targets, message text, preserved user-owned file contents, and state-file ordering rather than byte-for-byte file output.

### Implementation Steps

- [x] Add reusable scaffold/runtime refresh helpers for layered CLI and centralized devcontainer layouts that recreate missing managed files for a selected agent without clobbering user-owned override or policy files
- [x] Port `switch`, including optional agent selection, same-agent refresh behavior, running-runtime restart ordering, and active-target state updates
- [x] Port `edit compose` and `edit policy`, reusing the native editor helper and matching current file-selection, change-detection, restart, and warning semantics
- [x] Port `destroy`, including confirmation/force flow, layered and legacy compose shutdown handling, and cleanup that continues past compose-stop failures
- [x] Decide whether the default Go runtime syncer should become scaffold-backed in this task; implement it if needed to match Bash refresh semantics for mutating runtime commands without pulling `bump` work forward
- [x] Add Go tests covering legacy-layout failures, same-agent refresh, inactive-agent policy warnings, no-restart behavior, proxy/container restart calls, preserved user-owned files, and destroy cleanup/failure-continue paths
- [x] Verify `go test ./...`, `go build ./cmd/agentbox`, and representative `go run ./cmd/agentbox switch|edit|destroy` flows in temp repos with stubbed Docker and editor behavior

### Open Questions

None after execution. The default Go runtime syncer now uses the native scaffold refresh helpers, and the compose/exec command paths re-resolve the compose stack after sync so newly recreated override files are actually included in the Docker invocation.

## Outcome

Implemented real Go versions of `switch`, `edit compose`, `edit policy`, and `destroy`, added scaffold-backed lifecycle refresh helpers for layered CLI and centralized devcontainer layouts, and replaced the previous noop default runtime syncer so mutating compose commands now refresh managed files with the same ownership boundaries as the Bash CLI.

### Acceptance Verification

- [x] `agentbox switch` preserves shared and agent-specific overrides while refreshing the selected runtime correctly via `internal/cli/switch_test.go` coverage for same-agent refresh, live restart ordering, preserved user-owned files, devcontainer refresh, invalid-agent ordering, and uninitialized repos.
- [x] `agentbox edit compose` and `agentbox edit policy` target the same user-owned files and apply the same restart/warning semantics as today via `internal/cli/edit_test.go`, including legacy-layout failures, shared override targeting, inactive-agent policy warnings, no-restart behavior, proxy-only restart, and centralized devcontainer `--mode devcontainer` targeting.
- [x] `agentbox destroy` removes layered runtime files and compose resources with the current confirmation behavior via `internal/cli/destroy_test.go`, including layered cleanup, legacy compose cleanup, failure-continue behavior, no-stack warnings, and interactive abort.
- [x] Regression coverage exists for legacy-layout failures and same-agent refresh paths through the new lifecycle command tests plus the default runtime-sync regression in `internal/cli/runtime_commands_test.go`.

### Learnings

- Once runtime sync can recreate missing compose layers, commands must resolve the compose file list after sync rather than before it; otherwise Docker runs with a stale stack and silently omits newly restored override files.
- The native scaffold writers from `m13.3` are sufficient for lifecycle parity as long as refresh helpers preserve the distinction between agentbox-managed compose layers and user-owned override/policy files.

### Follow-up Items

- `m13.5` parity work should keep explicit regression coverage around post-sync compose-file re-resolution, because it is an easy place for future refactors to drift back toward stale file lists.
