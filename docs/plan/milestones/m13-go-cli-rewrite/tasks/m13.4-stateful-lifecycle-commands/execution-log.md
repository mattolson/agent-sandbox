# Execution Log: m13.4 - Stateful Lifecycle Commands

## 2026-04-03 05:04 UTC - Lifecycle commands and scaffold-backed runtime sync implemented

Replaced the pending Go CLI placeholders with real `switch`, `edit compose`, `edit policy`, and `destroy` commands; added shared lifecycle helpers in `internal/runtime` plus scaffold-backed refresh helpers in `internal/scaffold` for layered CLI and centralized devcontainer layouts; and added command-level regression tests covering same-agent refresh, preserved user-owned files, inactive-agent policy warnings, restart behavior, legacy-layout failures, and destroy cleanup paths. I also replaced the default noop runtime syncer with a scaffold-backed implementation and updated the runtime compose paths to re-resolve the stack after sync.

**Issue:** The first scaffold-backed runtime-sync pass exposed a parity bug in the already-ported runtime commands: `compose up/run/start/restart` and the `exec` startup path resolved the compose file list before sync, so newly recreated override files existed on disk but were still omitted from the actual Docker command.
**Solution:** Re-resolve the compose stack immediately after sync in the runtime command paths and in edit-triggered restart flows so the Docker invocation uses the refreshed file set.

**Decision:** Replace the default noop Go runtime syncer in `m13.4` instead of deferring it. Once native scaffold generation existed, keeping the noop path would have left the lifecycle commands and mutating compose commands with two different refresh behaviors and weakened parity before `m13.5`.

**Learning:** When lifecycle commands share a native scaffold layer, the risky part is no longer writing the files but preserving command ordering around them: validate before legacy checks, scaffold before switching stacks, write state only after `down` during live switches, and rebuild the compose-file list after sync before calling Docker.

## 2026-04-03 04:22 UTC - Planning complete

Reviewed the `m13.4` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, `docs/plan/learnings.md`, decision `004`, the completed `m13.2` and `m13.3` task artifacts, the current Go placeholders and native helpers in `internal/cli/root.go`, `internal/cli/runtime_commands.go`, `internal/runtime/{compose,legacy,state,editor}.go`, and `internal/scaffold/{init,compose,policy,devcontainer}.go`, plus the Bash lifecycle entrypoints in `cli/libexec/{switch,edit,destroy}` together with their BATS coverage in `cli/test/{switch,edit,destroy}`.

The main planning conclusion is that `m13.4` should keep the Cobra commands thin, add reusable Go refresh helpers around the native scaffold layer from `m13.3`, and use fixture-driven tests to protect user-owned override and policy files while matching restart and warning semantics for `switch`, `edit`, and `destroy`.

**Issue:** The current lifecycle behavior is split across Bash entrypoints, low-level scaffold helpers, and a Go CLI that already has runtime resolution, state parsing, editor handling, and a dormant runtime-sync seam. Duplicating that logic inside each new command would make parity harder to prove and increase the risk of clobbering user-owned files.
**Solution:** Plan the port around shared runtime/scaffold helpers: one path for resolving initialized layouts and active-target state, one path for refreshing managed files without rewriting user-owned overrides, and command handlers that focus only on flags, subprocess execution, and parity-focused user messaging.

**Decision:** Keep `destroy` as the cleanup escape hatch rather than a strict legacy-layout failure path. It should preserve the current ability to stop legacy compose stacks and then continue filesystem cleanup, while `switch` and `edit` continue to fail fast on unsupported legacy single-file layouts.

**Learning:** The highest-risk parity points are the state transitions around lifecycle events, not just the Docker command text: same-agent refresh versus true no-op, writing `active-target.env` only after `down` during a live switch, and restarting only the affected service when edit-time changes land on active configuration.
