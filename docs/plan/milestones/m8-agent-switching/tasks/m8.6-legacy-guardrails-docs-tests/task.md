# Task: m8.6 - Legacy Guardrails + Docs/Tests

## Summary

Finish milestone 8 by replacing the remaining silent legacy-layout fallbacks with explicit upgrade guidance, expanding regression coverage around non-destructive switching, converting broad init regression checks to effective rendered compose assertions, and updating docs to match the centralized `.agent-sandbox/` runtime model.

## Scope

- Detect pre-m8 single-file CLI and devcontainer layouts and fail fast in normal runtime/edit/switch/bump flows with actionable upgrade guidance
- Add or update BATS coverage for switch prompt behavior, invalid-agent validation, user-owned compose/policy preservation, and the no-`down --volumes` invariant
- Convert `cli/test/init/regression.bats` to assert against effective `docker compose config --no-interpolate` output, while keeping a minimal set of raw-file assertions for ownership and scaffolding details
- Add a dedicated upgrade guide markdown document for legacy single-file projects moving to the layered layout introduced in `m8`, and point legacy-layout errors at that document for fuller instructions
- Refresh README and CLI/policy docs so the switching workflow, `.devcontainer` sync behavior, centralized runtime ownership, and legacy upgrade path are described consistently
- Keep automatic migration tooling, concurrent-target UX, and a switch-time runtime reconciliation change out of scope
- Keep `destroy` as a likely cleanup exception unless implementation shows that a different guardrail boundary is safer

## Acceptance Criteria

- [x] Legacy single-file layouts are detected before normal runtime/edit/switch/bump flows proceed, and the failure message includes concrete upgrade guidance plus the current layered destination files
- [x] Legacy-layout failures point to a dedicated upgrade guide that explains the layout change, the rename-legacy-files flow, the `init` rerun, and where user customizations now belong
- [x] `switch` BATS cover zero-or-one prompt behavior, invalid `--agent` handling, preservation of user-owned compose overrides, preservation of shared and agent policy overrides, and absence of destructive `down --volumes` behavior
- [x] `cli/test/init/regression.bats` validates effective compose output through `docker compose config --no-interpolate`, with only a minimal residue of raw-file assertions for scaffolding and ownership behavior
- [x] README, `cli/README.md`, `docs/policy/schema.md`, and the dedicated upgrade guide explain the switching workflow, same-agent `.devcontainer/devcontainer.user.json` resync behavior, centralized runtime ownership, and legacy upgrade guidance
- [x] `policy-cli-<agent>.yaml` is treated consistently as legacy layout, including in otherwise layered repos

## Applicable Learnings

- Default edit commands should keep pointing at shared cross-mode config unless the user explicitly asks for a mode-specific override
- For user-facing runtime config, one clear ownership directory is better than splitting runtime meaning across `.agent-sandbox/` and `.devcontainer/`
- Relative paths in compose files are resolved from the compose file's directory, so effective rendered-config assertions are a better long-term regression target than raw per-file checks alone
- Documentation artifacts belong in `docs/`, while task documents should record the plan, decisions, and execution trail

## Plan

### Files Involved

- `cli/lib/path.bash` - tighten legacy compose detection responsibilities and remove normal-command reliance on silent single-file fallback where appropriate
- `cli/lib/run-compose` - fail fast for unsupported legacy layouts in normal runtime flows, while preserving deterministic layered compose assembly for current projects
- `cli/libexec/init/init` - decide and implement whether init itself refuses to layer on top of detected legacy layouts
- `cli/libexec/switch/switch` - reject unsupported legacy layouts with upgrade guidance before mutating active-agent state
- `cli/libexec/edit/compose` and `cli/libexec/edit/policy` - stop opening legacy single-file surfaces as though they are still first-class
- `cli/libexec/bump/bump` - reject legacy layouts instead of silently bumping stale single-file compose
- `cli/libexec/destroy/destroy` - confirm whether destroy remains the one cleanup-oriented legacy-compatible command
- `cli/test/switch/switch.bats`, `cli/test/edit/compose.bats`, `cli/test/edit/policy.bats`, `cli/test/compose/run-compose.bats`, `cli/test/path/find_compose_file.bats`, `cli/test/init/init.bats`, `cli/test/init/regression.bats`, and `cli/test/bump/bump.bats` - align coverage with the new guardrails and regression strategy
- `README.md`, `cli/README.md`, `docs/policy/schema.md`, and a new upgrade guide such as `docs/upgrades/m8-layered-layout.md` - update user-facing guidance and remove wording that still treats legacy layouts as normal

### Approach

The remaining work is not just test debt. The repository still has live legacy fallbacks in compose discovery, runtime execution, edit flows, policy editing, bump, and related tests. Those fallbacks currently blur three separate cases that need different treatment:

1. pre-m8 single-file layouts that should now fail with explicit upgrade guidance
2. cleanup-oriented commands such as `destroy` that may still need a legacy-compatible path so users can remove old scaffolds safely

The recommended implementation is to introduce one explicit legacy-layout detector and upgrade-guidance formatter, then call it from the user-facing entrypoints that are supposed to operate only on layered layouts. That is safer than deleting every low-level fallback in place, because low-level helpers such as `find_compose_file` are also used by cleanup paths and tests.

The user-facing error should stay concise. It should:

- name the legacy files that were detected
- explain that current commands expect the layered `.agent-sandbox/compose/` and `.agent-sandbox/policy/` model
- summarize the safe upgrade flow: rename legacy generated files, rerun `agentbox init`, then copy customizations into user-owned layered files
- point to the dedicated upgrade guide for the full explanation of what changed in `m8`

The dedicated guide should be organized around the upgrade task, not around milestone internals. "Upgrade legacy single-file layouts to the layered runtime model introduced in m8" is the right framing. A pure "what changed in m8" changelog would be the wrong document for CLI error messages.

For regression coverage, shift the main assertions in `cli/test/init/regression.bats` from "did each generated file contain the expected fragment" to "does the composed stack render to the expected effective config." The likely shape is:

- generate the layered files for a fixture repo
- collect the relevant compose stack in CLI or devcontainer order
- run `docker compose ... config --no-interpolate`
- assert on the rendered output with `yq`

Keep raw-file assertions only for things rendered compose cannot prove, such as scaffold existence, user-owned file boundaries, and `devcontainer.user.json` behavior.

For switching coverage, prefer fixtures that contain concrete user edits in `.agent-sandbox/compose/user.override.yml`, `.agent-sandbox/compose/user.agent.<agent>.override.yml`, `.agent-sandbox/policy/user.policy.yaml`, and `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`, then prove that `switch` preserves those files and never reaches a destructive `down --volumes` path.

### Implementation Steps

- [x] Define the exact unsupported legacy-layout patterns and the upgrade message
- [x] Write the dedicated upgrade guide and wire the legacy-layout error messages to point at it
- [x] Wire legacy guardrails into the chosen user-facing commands and keep or remove `destroy` compatibility intentionally rather than accidentally
- [x] Update BATS coverage for switch behavior, legacy-layout failures, and any changed edit/bump/runtime semantics
- [x] Convert broad init regression checks to effective rendered-compose assertions and keep only the raw-file checks that still add signal
- [x] Refresh README and CLI/policy docs to match the implemented guardrails and switching workflow

### Open Questions

- Should `destroy` remain the only command that still tolerates legacy single-file layouts so users keep a cleanup path? Recommended: yes.
- Should `init` hard-fail when legacy files already exist, or should the guardrail apply only to switch/edit/runtime commands? Recommended: hard-fail to avoid silently mixing ownership models.
- For the "preserves volumes" acceptance point, should the test only assert "no `down --volumes`" or should it assert that `switch` does not mutate Docker runtime state at all in the current implementation? Recommended: keep the explicit negative `down --volumes` assertion and document that runtime reconciliation remains out of scope.

## Outcome

### Acceptance Verification

- [x] `cli/lib/legacy-layout.bash`, `cli/lib/run-compose`, `cli/libexec/init/init`, `cli/libexec/switch/switch`, `cli/libexec/edit/compose`, `cli/libexec/edit/policy`, and `cli/libexec/bump/bump` now fail fast on pre-`m8` single-file layouts with rename-and-rerun guidance, including `policy-cli-<agent>.yaml` in otherwise layered repos.
- [x] Legacy-layout failures now point to the dedicated guide at `docs/upgrades/m8-layered-layout.md`, which explains the `m8` layout shift, the `*.legacy.*` rename flow, the `init` rerun, and the new user-owned destination files.
- [x] BATS coverage now verifies switch prompt behavior, invalid-agent handling, user-owned compose and policy preservation, the no-Docker-mutation invariant for current `switch`, and legacy-layout failures for runtime and edit flows. Verified locally with `cli/support/bats/bin/bats` across `cli/test/edit/policy.bats`, `cli/test/switch/switch.bats`, `cli/test/init/init.bats`, `cli/test/compose/run-compose.bats`, `cli/test/edit/compose.bats`, and the filtered `bump fails fast` case in `cli/test/bump/bump.bats`.
- [x] `cli/test/init/regression.bats` now passes in a real `docker` + `yq` environment after helper compatibility fixes for Bash 3.2, BATS env injection, and Compose/YAML shape differences.
- [x] `README.md`, `cli/README.md`, `docs/policy/schema.md`, and `docs/upgrades/m8-layered-layout.md` now describe the switching workflow, same-agent `.devcontainer/devcontainer.user.json` resync behavior, centralized runtime ownership, and the legacy upgrade path.
- [x] `policy-cli-<agent>.yaml` is now treated consistently as legacy layout, including in otherwise layered repos. Verified in `cli/test/edit/policy.bats`.

### Learnings

- Put legacy-layout guardrails in user-facing entrypoints, not low-level path helpers, when one command such as `destroy` still needs a cleanup-compatible fallback.
- Keep CLI error messages short and point them at a dedicated upgrade guide when the migration story is larger than a few lines of stderr.
- Effective rendered-compose regression helpers need to normalize across tool versions; `docker compose config --no-interpolate` can render env and volume nodes in multiple valid shapes.

### Follow-up Items

- Run the full `cli/test/bump/bump.bats` in an environment that has both `docker` and `yq`.
