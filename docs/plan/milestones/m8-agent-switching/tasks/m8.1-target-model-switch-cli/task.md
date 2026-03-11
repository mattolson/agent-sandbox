# Task: m8.1 - Target Model and Switch CLI

## Summary

Add the first slice of agent switching infrastructure: a shared target-state model for the current agent, plus a new `agentbox switch` command that validates agent selection and updates that state without introducing destructive config rewrites.

## Scope

- Add a shared helper for supported-agent metadata, agent validation, and interactive agent selection
- Add persistent active-agent state under `.agent-sandbox/` so later tasks can consume a single source of truth
- Add `agentbox switch --agent <name>` to validate and update the active agent
- Update `agentbox init` to write the same active-agent state after a successful init
- Add BATS coverage for switch validation, prompting, and init/switch state writes
- Do not refactor compose layout in this task; managed vs user-owned compose layering stays in `m8.2`
- Do not refactor policy layering in this task; shared and agent policy merge stays in `m8.3`
- Do not sync `.devcontainer` sidecar files in this task; that stays in `m8.4`
- Do not claim non-destructive runtime reconciliation yet; `switch` in this task is control-plane plumbing, not the full end-state UX

## Acceptance Criteria

- [x] `agentbox switch --agent <claude|codex|copilot>` succeeds without prompting and writes the requested active agent to project state
- [x] `agentbox switch` prompts exactly once for agent selection when `--agent` is omitted
- [x] `agentbox switch --agent invalid` fails with the same supported-agent validation used by `init`
- [x] `agentbox init` writes the active-agent state after a successful scaffold so new projects start in sync
- [x] Shared agent validation/selection logic is used by both `init` and `switch`, avoiding duplicated supported-agent lists
- [x] BATS coverage exists for successful switch, invalid agent, prompt behavior, and missing-project-state guidance

## Applicable Learnings

- Devcontainer and compose flows use different files and ownership rules, so `m8.1` should stay mode-agnostic and avoid bundling `.devcontainer` mutations into the first switching slice
- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place; that argues for deferring destructive file rewrites until the layered layout work in `m8.2`
- The "baked default + optional override" pattern is the right direction for security-sensitive config, so the first task should establish state and command plumbing rather than invent transitional rewrite behavior
- Relative paths in compose files are resolved from the compose file directory, not the repo root; active-target state should therefore live outside compose path resolution helpers

## Plan

### Files Involved

- `cli/lib/agent.bash` - new shared helper for agent validation, selection, and active-agent state
- `cli/lib/logging.bash` - make terminal styling non-fatal in test and noninteractive environments
- `cli/libexec/init/init` - replace inline agent validation/selection with shared helpers and persist active-agent state after success
- `cli/libexec/switch/switch` - new command entrypoint for switch validation, prompt flow, and state updates
- `cli/test/init/init.bats` - extend to assert init writes state and shares validation behavior
- `cli/test/switch/switch.bats` - new BATS suite for the switch command
- `cli/README.md` - document the new `switch` command surface

### Approach

Introduce a small shared agent-state helper instead of copying more logic into `switch`. The current CLI hardcodes `available_agents=(claude copilot codex)` inside `init`, which will drift immediately if `switch` grows its own copy. The first step should be a shared helper that exposes:

- supported agents
- `validate_agent`
- `select_agent`
- active-target state path resolution
- active-target state read/write helpers

For the state format, use an extensible shell-friendly file such as `.agent-sandbox/active-target.env` rather than a raw one-line text file. That keeps Bash parsing simple in the current CLI and leaves room for future metadata without changing the file format.

`agentbox init` should call the shared helper after successful generation so new installs always have explicit state. `agentbox switch` should:

1. resolve the repo root
2. verify the sandbox has been initialized
3. accept `--agent` or prompt once if it is missing
4. validate the agent through the shared helper
5. write the active-target state
6. exit with a clear no-op message if the requested agent is already active

This task should deliberately stop there. The current single-file compose layout cannot deliver the milestone's full non-destructive switching promise yet. Trying to make `switch` rewrite compose or policy files before `m8.2` and `m8.3` land would either be destructive or create transitional logic that must be thrown away.

### Implementation Steps

- [x] Add a shared helper for supported agents and active-target state read/write
- [x] Refactor `init` to consume the shared helper and persist active-target state
- [x] Add `cli/libexec/switch/switch`
- [x] Add tests for `switch --agent`, interactive `switch`, invalid agents, same-agent no-op, and missing sandbox state
- [x] Run the affected BATS suites and adjust plan details if command behavior changes during implementation

### Open Questions

None.

## Outcome

### Acceptance Verification

- [x] `agentbox switch --agent <claude|codex|copilot>` writes `.agent-sandbox/active-target.env` and exits without prompting, covered by `cli/test/switch/switch.bats`
- [x] `agentbox switch` prompts exactly once when `--agent` is omitted, covered by `cli/test/switch/switch.bats`
- [x] `agentbox switch --agent invalid` fails through the shared validator with the same supported-agent set used by `init`
- [x] `agentbox init` writes the active-agent state after successful CLI and devcontainer scaffolds, covered by `cli/test/init/init.bats`
- [x] Shared validation/selection logic now lives in `cli/lib/agent.bash` and is consumed by both `init` and `switch`
- [x] Targeted verification passed: `cli/test/logging/logging.bats`, `cli/test/init/init.bats`, and `cli/test/switch/switch.bats`

### Learnings

- `tput` can fail under noninteractive or `TERM=dumb` test environments, and the logger must treat styling as best-effort rather than fatal.
- The current broader `test/init/` suite assumes `yq` is installed. For this task, the directly affected suites passed, but full init regression coverage in this container still needs `yq` available.

### Follow-up Items

- `m8.2` still needs to connect the active-agent state to layered compose selection and non-destructive runtime reconciliation.
