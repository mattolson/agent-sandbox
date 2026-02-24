# Task: m7.4 - CLI Init and Build Script Integration

## Summary

Wire Codex into the CLI init flow and build script.

## Scope

- Add `codex` to `available_agents` array in `cli/libexec/init/init`
- Add `CODEX_VERSION` variable and `build_codex()` function to `images/build.sh`
- Add `codex` to the `all` build target
- Update build.sh usage documentation
- Update BATS test assertion for agent list

## Acceptance Criteria

- [x] `agentbox init` shows codex as an option in interactive mode
- [x] `agentbox init --agent codex` works in non-interactive mode
- [x] `./images/build.sh codex` builds the image
- [x] `./images/build.sh all` includes codex
- [x] BATS tests pass with updated agent list

## Plan

### Files Involved

- `cli/libexec/init/init` (modify)
- `images/build.sh` (modify)
- `cli/test/init/init.bats` (modify)

### Implementation Steps

- [x] Add `codex` to `available_agents` in init script
- [x] Update init script comment to list codex
- [x] Add `CODEX_VERSION`, `CODEX_EXTRA_PACKAGES` defaults to build.sh
- [x] Add `build_codex()` function to build.sh
- [x] Add `codex` to case statement and `all` target in build.sh
- [x] Update build.sh usage text
- [x] Update BATS test assertion for agent list validation

## Outcome

### Acceptance Verification

- [x] `codex` added to `available_agents` array - init will show it in interactive selection and accept it via `--agent codex`
- [x] `build_codex()` follows exact pattern of `build_copilot()` - passes `BASE_IMAGE`, `CODEX_VERSION`, `EXTRA_PACKAGES`
- [x] `codex` in case statement and `all` target
- [x] BATS test updated to expect `claude copilot codex` in error message

### Learnings

- BATS tests assert on the exact agent list string in error messages. Adding a new agent requires updating these assertions.

### Follow-up Items

None.
