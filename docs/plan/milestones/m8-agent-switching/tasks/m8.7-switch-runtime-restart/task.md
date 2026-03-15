# Task: m8.7 - Restart Running Services On Agent Switch

## Summary

Finish the runtime-reconciliation piece of `agentbox switch` so that changing the active agent does not leave already-running containers on the old config.

## Scope

- Detect whether the current layered compose stack is running before the active agent changes
- After switching to a different agent, run `docker compose down` and `docker compose up -d` through the existing layered compose wrapper when services were already running
- Leave stopped projects alone so `switch` remains a control-plane change when nothing is active
- Update switch-focused BATS coverage and CLI docs to match the new behavior
- Do not add `--no-restart` or other switch-specific flags in this task
- Do not change the same-agent refresh path in this task

## Acceptance Criteria

- [x] Switching to a different agent restarts the running compose stack with `down` then `up -d`
- [x] Switching to a different agent does not start containers when the project is currently stopped
- [x] The active-agent state is still updated before the restarted stack comes back up
- [x] BATS coverage exists for both the running and stopped branches
- [x] CLI documentation states that `switch` reconciles a running stack immediately

## Applicable Learnings

- Runtime commands should respect current container state instead of blindly recreating services; unnecessary restarts can kill active sessions, but missing a required restart leaves the visible runtime inconsistent with the selected config
- Keep command behavior explicit in docs when runtime side effects change, especially for `switch` and other stateful CLI operations
- Reuse the existing layered compose wrapper instead of adding a second compose resolution path

## Plan

### Files Involved

- `cli/libexec/switch/switch` - detect the pre-switch running state and restart the stack after an actual agent change
- `cli/test/switch/switch.bats` - replace the old no-docker expectation with running and stopped restart coverage
- `cli/README.md` - document the restart behavior for running stacks

### Approach

Capture the running state before changing the active-agent pointer, because that state belongs to the currently selected compose stack. After target runtime files are ensured and the active agent is written, reuse `run-compose` to apply the selected agent's stack. If the earlier running-state probe returned any container IDs, run `down` and then `up -d`; otherwise, just write the new active agent and exit.

The probe stays out of the same-agent refresh path. That path is still intended to refresh generated runtime files without treating the operation as a full switch.

### Implementation Steps

- [x] Probe the current stack's running state before switching away from the active agent
- [x] Restart the stack after writing the new active agent when the probe shows running containers
- [x] Update switch tests for running and stopped projects
- [x] Update CLI docs for the new switch side effect
- [x] Run the targeted switch BATS suite

### Open Questions

None.

## Outcome

### Acceptance Verification

- [x] Switching to a different agent now runs `down` then `up -d` when the current stack is running, implemented in `cli/libexec/switch/switch`
- [x] Stopped projects keep the previous behavior and only update `.agent-sandbox/active-target.env`
- [x] The restart uses the newly written active-agent state, so `up -d` comes back on the selected agent's compose layer
- [x] `cli/test/switch/switch.bats` covers both the running and stopped branches
- [x] `cli/README.md` documents the immediate restart behavior for running stacks

### Learnings

- The right probe point is before the active-agent write, but the right restart point is after it. Mixing those two concerns would either inspect the wrong stack or bring the wrong agent back up.
- The old `m8.1` test assertion that switch never touched Docker had become a stale artifact once layered runtime selection was fully wired in.

### Follow-up Items

- Consider whether the same-agent refresh path should eventually offer an explicit runtime reconciliation option when regenerated files differ materially.
