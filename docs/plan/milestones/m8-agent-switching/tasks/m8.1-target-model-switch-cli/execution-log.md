# Execution Log: m8.1 - Target Model and Switch CLI

## 2026-03-11 22:22 UTC - Implementation complete

Added `cli/lib/agent.bash` for shared agent validation, prompting, and `.agent-sandbox/active-target.env` management. Updated `init` to use the shared helper and persist active-agent state, added `cli/libexec/switch/switch`, documented the new command in `cli/README.md`, and added `cli/test/switch/switch.bats`.

**Issue:** The first targeted test run failed before reaching the new logic because `tput` returned non-zero under the BATS environment, causing the logger to stop after the timestamp.
**Solution:** Added `safe_tput()` in `cli/lib/logging.bash` so terminal styling is best-effort and never aborts the command path.

**Decision:** `switch` treats an already-active agent as a successful no-op and requires only an initialized `.agent-sandbox/` directory, not future layered-layout files.

**Learning:** Shared command plumbing in the shell CLI is cheap to add once the logic moves into a library; the harder part is guarding old helper code against noninteractive environments.

## 2026-03-11 22:21 UTC - Verification pass

Ran targeted verification for the touched paths:

- `cli/test/logging/logging.bats`
- `cli/test/init/init.bats`
- `cli/test/switch/switch.bats`

Also ran the broader `test/init/` suite and found an environment gap in this container: the policy and regression suites require `yq`, which is not installed here.

**Issue:** `test/init/policy.bats` and `test/init/regression.bats` fail with `yq required`.
**Solution:** Treat that as an environment limitation for this turn and rely on the directly affected suites that do pass.

## 2026-03-11 22:18 UTC - Execution started

User approved execution and resolved the open design question: active target identity is `agent`, not `{mode, agent}`.

Updated the switching decision doc plus the stale project-plan and roadmap entries that still documented `switch` as mode-aware. Also updated the task plan to remove the now-resolved open question before touching code.

**Decision:** Treat runtime mode as separate context. `m8.1` persists only the active agent in project state.

## 2026-03-11 22:09 UTC - Planning complete

Reviewed the `m8` milestone plan, `docs/plan/learnings.md`, decisions `003` and `004`, and the current shell CLI implementation in `cli/bin/agentbox`, `cli/lib/path.bash`, `cli/lib/select.bash`, and `cli/libexec/init/init`.

The main planning conclusion is that `m8.1` should stay narrow: shared agent-state plumbing plus a new `switch` command. The current CLI still uses a single generated compose file and duplicates supported-agent logic inside `init`, so trying to deliver the full non-destructive switching UX in this task would either be destructive or require transitional code that `m8.2` would immediately replace.

**Issue:** The milestone document treats active target identity as `agent`, while decision `004` still says `{mode, agent}`.
**Solution:** Treat the milestone as the current UX source of truth for `m8.1`, but plan the state format so it can grow without a migration if `mode` needs to be recorded later.

**Decision:** Scope `m8.1` to shared validation/selection helpers, persistent active-target state, `agentbox switch`, and BATS coverage. Leave layered compose, policy merge, and `.devcontainer` sync to `m8.2` through `m8.4`.

**Learning:** Command dispatch is already module-directory based, so adding `cli/libexec/switch/` is straightforward. The higher-risk part is eliminating duplicated agent-selection logic so `init` and `switch` cannot drift.
