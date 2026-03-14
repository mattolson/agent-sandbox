# Task: m8.5 - Centralize Devcontainer Runtime Files

## Summary

Refactor the `m8.4` devcontainer layout so `.devcontainer/` becomes a thin IDE shim and all sandbox runtime files live in `.agent-sandbox/`. Keep `devcontainer.json` and optional `devcontainer.user.json` under `.devcontainer/`, but move devcontainer compose and policy layers into `.agent-sandbox/` and do not add devcontainer-specific user compose/policy override files unless demand appears later.

## Scope

- Move the managed devcontainer compose layer out of `.devcontainer/` and into `.agent-sandbox/compose/`
- Move the managed devcontainer policy layer out of `.devcontainer/` and into `.agent-sandbox/`
- Keep only `.devcontainer/devcontainer.json` and `.devcontainer/devcontainer.user.json` as user-visible devcontainer files
- Reuse `.agent-sandbox/compose/user.override.yml` and `.agent-sandbox/compose/user.agent.<agent>.override.yml` for devcontainer workflows instead of scaffolding devcontainer-specific user compose override files
- Reuse `.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<agent>.policy.yaml` for user-owned policy edits; do not expose a devcontainer-specific user policy file for now
- Update `init`, `switch`, compose/path helpers, edit flows, policy rendering, and docs to match the centralized ownership model
- Keep broad migration tooling out of scope; narrow fallback or guardrails for the short-lived `m8.4` layout are acceptable if needed for command safety

## Acceptance Criteria

- [x] `agentbox init --mode devcontainer` creates `.devcontainer/devcontainer.json` and `.devcontainer/devcontainer.user.json`, but no managed or user-owned devcontainer compose/policy files under `.devcontainer/`
- [x] The devcontainer compose stack is sourced from `.agent-sandbox/compose/` and uses the same shared and agent-specific user override files as CLI mode, with one managed devcontainer mode overlay
- [x] Devcontainer policy enforcement reuses the `m8.3` render path with one managed `.agent-sandbox/policy.devcontainer.yaml` layer and no devcontainer-specific user policy file
- [x] `agentbox switch --agent <name>` refreshes the centralized devcontainer runtime files for the selected agent, regenerates `.devcontainer/devcontainer.json`, preserves `.devcontainer/devcontainer.user.json`, and does not ask extra IDE questions
- [x] `agentbox edit compose` continues to target `.agent-sandbox/compose/user.override.yml`, and `agentbox edit policy --mode devcontainer` no longer opens a separate user-editable file
- [x] Docs explain the new mental model clearly: `.devcontainer/` is IDE discovery only, `.agent-sandbox/` owns sandbox runtime and policy state

## Applicable Learnings

- Devcontainer and compose flows serve different consumers, so `devcontainer.json` should stay separate even when compose and policy move under `.agent-sandbox/`
- Relative paths in compose files are resolved from the compose file's directory; centralizing the compose stack under one directory is simpler than mixing runtime files across `.agent-sandbox/` and `.devcontainer/`
- Default edit commands should keep pointing at shared cross-mode config unless the user explicitly asks for a mode-specific override
- Devcontainer-specific policy rules should be additive layers on top of the shared `.agent-sandbox` policy files, not a second standalone source of truth

## Plan

### Files Involved

- `cli/lib/cli-compose.bash` - extend the layered compose backend with a managed devcontainer mode overlay that can be reused by CLI helpers and `devcontainer.json`
- `cli/lib/devcontainer.bash` - stop treating `.devcontainer/` compose/policy files as the primary runtime layout, regenerate only `devcontainer.json`, and keep `devcontainer.user.json` as the lone user-owned devcontainer extension point
- `cli/lib/path.bash` and `cli/lib/run-compose` - prefer the centralized `.agent-sandbox` devcontainer compose stack while keeping short-lived `m8.4` layouts safe during the transition
- `cli/libexec/init/devcontainer` and `cli/libexec/init/init` - generate the new centralized layout and stop scaffolding devcontainer-specific compose/policy override files
- `cli/libexec/switch/switch` - refresh the centralized devcontainer runtime layers and re-render `devcontainer.json` for the selected agent
- `cli/libexec/edit/compose` and `cli/libexec/edit/policy` - remove the devcontainer-specific edit surfaces for compose and policy
- `cli/templates/compose/` - add the managed `mode.devcontainer.yml` overlay or equivalent shared template
- `cli/templates/devcontainer/` - keep only `devcontainer.user.json`; move managed compose/policy defaults out of this directory
- `cli/templates/<agent>/devcontainer/devcontainer.json` - reference the centralized `.agent-sandbox/compose/*.yml` stack from `.devcontainer/devcontainer.json`
- `images/proxy/render-policy` - switch the devcontainer managed policy input from `.devcontainer/policy.override.yaml` to `.agent-sandbox/policy.devcontainer.yaml`
- `cli/test/init/init.bats`, `cli/test/init/regression.bats`, `cli/test/switch/switch.bats`, `cli/test/compose/run-compose.bats`, `cli/test/edit/compose.bats`, `cli/test/edit/policy.bats`, `cli/test/path/find_compose_file.bats`, and `cli/test/policy/render.bats` - update expectations for the centralized layout
- `README.md`, `cli/README.md`, and `docs/policy/schema.md` - rewrite the user-facing layout explanation around the new single-runtime-directory model

### Approach

The `m8.4` layout improved ownership boundaries but created a second problem: runtime meaning is now split across `.agent-sandbox/` and `.devcontainer/`. Users have to understand that the shared and agent-specific policy files live in one directory while devcontainer mode adds extra policy and compose layers from another directory. That is conceptually heavier than the security model requires.

The refactor should make `.devcontainer/` an IDE shim only:

- `.devcontainer/devcontainer.json` remains the editor-discovery entrypoint
- `.devcontainer/devcontainer.user.json` remains the only user-owned devcontainer-specific extension surface
- All compose and policy runtime files move to `.agent-sandbox/`

Recommended compose model:

1. `.agent-sandbox/compose/base.yml`
2. `.agent-sandbox/compose/agent.<agent>.yml`
3. `.agent-sandbox/compose/mode.devcontainer.yml` when running through devcontainer
4. `.agent-sandbox/compose/user.override.yml`
5. `.agent-sandbox/compose/user.agent.<agent>.override.yml` when present

`devcontainer.json` should reference those compose files with paths relative to `.devcontainer/devcontainer.json` (for example `../.agent-sandbox/compose/base.yml`). Because Docker Compose paths are evaluated from the compose file location, centralizing the entire compose stack in one directory avoids the mixed-directory path hazards that the `m8.4` layout introduced.

Recommended policy model:

1. active-agent baseline (`services: [<active-agent>]`)
2. `.agent-sandbox/user.policy.yaml`
3. `.agent-sandbox/user.agent.<active-agent>.policy.yaml`
4. `.agent-sandbox/policy.devcontainer.yaml` when running through devcontainer

Do not add `.agent-sandbox/user.devcontainer.policy.yaml` yet. The current evidence does not justify a separate user-editable devcontainer policy surface, and keeping `agentbox edit policy` pointed at the shared file is simpler. `agentbox edit policy --mode devcontainer` should stop pretending there is a dedicated user file; the cleanest likely behavior is a clear error telling the user to edit `.agent-sandbox/user.policy.yaml` instead.

This task should also normalize terminology in the code and docs. The user-facing model should be:

- `.devcontainer/` = IDE discovery and editor-facing JSON
- `.agent-sandbox/` = sandbox runtime, compose, and policy state

### Implementation Steps

- [x] Update the milestone/task docs to capture the centralized layout decision and note that devcontainer-specific user compose/policy override files are intentionally deferred
- [x] Add a managed devcontainer compose overlay under `.agent-sandbox/compose/` and point `devcontainer.json` at the centralized compose stack
- [x] Move the managed devcontainer policy layer into `.agent-sandbox/` and update the render path to consume it
- [x] Remove scaffolding and edit-path support for devcontainer-specific compose/policy user override files
- [x] Update `switch`, path detection, and compose helpers to treat the centralized layout as primary while keeping `m8.4` repos safe
- [x] Refresh docs and targeted regression coverage around the new ownership model

### Resolved Questions

- `agentbox edit policy --mode devcontainer` now fails clearly for the centralized layout instead of aliasing to the shared file, because silently opening `.agent-sandbox/user.policy.yaml` would make the mode flag misleading.
- The temporary `m8.4` layout does not keep any runtime compatibility branch, because milestone 8 has not shipped to users yet. This task removes the abandoned `.devcontainer` compose/policy path instead of preserving it.

## Outcome

### Acceptance Verification

- [x] `cli/lib/devcontainer.bash`, `cli/lib/cli-compose.bash`, and the new templates at `cli/templates/compose/mode.devcontainer.yml` and `cli/templates/policy.devcontainer.yaml` now centralize the devcontainer runtime layers under `.agent-sandbox/`.
- [x] `cli/templates/<agent>/devcontainer/devcontainer.json` now points at the centralized compose stack, while `.devcontainer/devcontainer.user.json` remains the only devcontainer-specific user-owned extension surface.
- [x] `cli/libexec/edit/compose` now keeps devcontainer projects on `.agent-sandbox/compose/user.override.yml`, and `cli/libexec/edit/policy` now rejects `--mode devcontainer` for the centralized layout instead of opening a fake separate user file.
- [x] `cli/lib/run-compose`, `cli/lib/path.bash`, and `cli/libexec/switch/switch` now treat the centralized devcontainer stack as primary while preserving a narrow fallback for short-lived `m8.4` layouts.
- [x] README, CLI docs, and policy schema docs now describe `.devcontainer/` as IDE discovery only and `.agent-sandbox/` as the runtime/policy home.
- [x] Targeted verification passed with `cli/support/bats/bin/bats` across `cli/test/init/init.bats`, `cli/test/switch/switch.bats`, `cli/test/compose/run-compose.bats`, `cli/test/path/find_compose_file.bats`, `cli/test/edit/compose.bats`, `cli/test/edit/policy.bats`, and `cli/test/policy/render.bats`.

### Learnings

- Reusing the layered CLI backend for devcontainer mode simplified the code more than trying to preserve a separate devcontainer compose stack with "nicer" locality.
- A clean ownership split on paper is not enough if users have to reason across two directories to understand one runtime.
- Removing unreleased intermediate layouts is better than carrying a compatibility story for them. The only compatibility work worth keeping is for layouts users have actually received.

### Follow-up Items

- `m8.6` still needs explicit legacy-layout guardrails and upgrade guidance for the pre-m8 shipped layouts.
- `cli/test/init/regression.bats` still was not run in this environment because there is no real `yq` binary available.
