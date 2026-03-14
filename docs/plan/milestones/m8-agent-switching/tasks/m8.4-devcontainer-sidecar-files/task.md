# Task: m8.4 - Devcontainer Sidecar Files

## Summary

Replace the remaining single-file devcontainer scaffold with managed `.devcontainer` sidecar files plus user-owned `.devcontainer/*user*` extension points, then sync those managed sidecars to the active agent on `init` and `switch` without reintroducing destructive rewrites.

## Scope

- Replace the single managed devcontainer compose/policy scaffold with these managed sidecars: `.devcontainer/devcontainer.json`, `.devcontainer/docker-compose.base.yml`, and `.devcontainer/policy.override.yaml`
- Add these user-owned devcontainer extension points: `.devcontainer/devcontainer.user.json`, `.devcontainer/docker-compose.user.override.yml`, and `.devcontainer/policy.user.override.yaml`
- Update `agentbox init --mode devcontainer` to create the managed sidecars and any missing user-owned devcontainer files without overwriting existing user-owned files
- Update `agentbox switch --agent <name>` to resync the managed `.devcontainer/` sidecars for the selected agent while preserving all `.devcontainer/*user*` files
- Reuse the proxy-side policy render path from `m8.3`, adding devcontainer managed/user override layers instead of keeping `policy-devcontainer-<agent>.yaml` as a separate source of truth
- Keep CLI layered compose/runtime behavior intact; do not rework the CLI merge model or add concurrent-target UX here
- Keep legacy-layout guardrails and broader upgrade messaging out of scope; that remains `m8.5`

## Acceptance Criteria

- [x] `agentbox init --mode devcontainer` creates managed `.devcontainer/devcontainer.json`, `.devcontainer/docker-compose.base.yml`, and `.devcontainer/policy.override.yaml`, plus `.devcontainer/devcontainer.user.json`, `.devcontainer/docker-compose.user.override.yml`, and `.devcontainer/policy.user.override.yaml` when missing, without overwriting existing user-owned devcontainer files
- [x] The effective devcontainer compose stack is deterministic and non-destructive: managed `.devcontainer/docker-compose.base.yml` is layered before optional `.devcontainer/docker-compose.user.override.yml` for both IDE use and CLI compose helpers
- [x] Devcontainer proxy enforcement reuses the `m8.3` render path, layering the active-agent baseline with `.agent-sandbox/user.policy.yaml`, `.agent-sandbox/user.agent.<agent>.policy.yaml`, `.devcontainer/policy.override.yaml`, and optional `.devcontainer/policy.user.override.yaml`
- [x] `agentbox switch --agent <name>` rewrites only the managed devcontainer sidecars for the target agent, preserves all `.devcontainer/*user*` files, and does not ask any extra IDE questions during switch
- [x] The selected devcontainer IDE behavior remains stable across `switch` by persisting the chosen IDE and project name as auxiliary metadata in `.agent-sandbox/active-target.env`
- [x] `agentbox edit compose` opens `.devcontainer/docker-compose.user.override.yml` for sidecar projects, while `agentbox edit policy --mode devcontainer` opens `.devcontainer/policy.user.override.yaml` and the default policy edit surface remains `.agent-sandbox/user.policy.yaml`
- [x] Docs and generated file guidance clearly distinguish managed vs user-owned `.devcontainer` files and tell users to reopen or rebuild the devcontainer after a switch

## Applicable Learnings

- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place
- Devcontainer and CLI compose flows use different files and ownership rules, so `m8.4` should add devcontainer sidecars without disturbing the layered CLI backend from `m8.2`
- `run-compose` is the practical compatibility boundary for layered CLI mode, so devcontainer-sidecar support should fit existing compose helper patterns instead of creating another one-off runtime path
- Reusing the proxy-side merge implementation avoided shell/runtime drift in `m8.3`; devcontainer policy overrides should plug into that same render path
- `devcontainer.json` and Docker Compose serve different roles, so the plan should keep devcontainer JSON rendering separate from compose/policy layering
- Relative paths in compose files are resolved from the compose file's directory, so every `.devcontainer/*` mount and policy path needs explicit path review

## Plan

### Files Involved

- `cli/lib/path.bash` - add helpers for detecting the new devcontainer sidecar layout and locating the managed/user override compose files
- `cli/lib/devcontainer.bash` - new shared helper for devcontainer sidecar paths, scaffolding, and state-aware sync
- `cli/lib/run-compose` - support the devcontainer sidecar compose stack (`docker-compose.base.yml` plus optional `docker-compose.user.override.yml`) when CLI layered compose is not in use
- `cli/lib/policyfile.bash` - add scaffold helpers for devcontainer managed/user policy override files and remove reliance on `policy-devcontainer-<agent>.yaml`
- `cli/libexec/init/devcontainer` - replace single-file copy/customization with managed sidecar scaffolding and rendered `devcontainer.json` output
- `cli/libexec/init/init` - update devcontainer init flow, review prompts, and any persisted devcontainer IDE metadata
- `cli/libexec/switch/switch` - sync managed devcontainer sidecars for the target agent while preserving user-owned files
- `cli/libexec/edit/compose` - open `.devcontainer/docker-compose.user.override.yml` for sidecar-based devcontainer projects
- `cli/libexec/edit/policy` - open `.devcontainer/policy.user.override.yaml` for sidecar-based devcontainer projects
- `cli/templates/<agent>/devcontainer/` - split the current full devcontainer templates into managed sidecar templates per agent
- `cli/templates/devcontainer/` - add shared user-owned scaffold templates for `docker-compose.user.override.yml`, `policy.user.override.yaml`, and any rendered `devcontainer.user.json` base content
- `images/proxy/render-policy` and devcontainer compose templates - accept optional devcontainer policy layers so proxy runtime and `agentbox policy render` keep one merge path
- `cli/test/init/init.bats` and `cli/test/init/regression.bats` - update scaffolding expectations, prompts, and rendered devcontainer outputs
- `cli/test/switch/switch.bats` - add coverage for managed devcontainer sidecar sync and preservation of `.devcontainer/*user*` files
- `cli/test/edit/compose.bats` and `cli/test/edit/policy.bats` - update editable-surface behavior for devcontainer sidecar layouts
- `cli/test/compose/run-compose.bats` and `cli/test/path/find_compose_file.bats` - verify devcontainer sidecar stack resolution
- `cli/README.md`, `README.md`, and `docs/policy/schema.md` - document managed vs user-owned devcontainer files, compose/policy layering, and reopen/rebuild workflow after `switch`

### Approach

The current devcontainer path is still the pre-`m8` model: `init` copies a full per-agent `.devcontainer/` template, customizes one `docker-compose.yml`, and writes a separate flat `.agent-sandbox/policy-devcontainer-<agent>.yaml`. That conflicts with the milestone's ownership model in three ways:

1. the whole devcontainer scaffold is managed as one blob
2. user edits have no protected extension point inside `.devcontainer/`
3. devcontainer policy is not on the shared render path that `m8.3` introduced for CLI mode

Recommended structure:

- Managed, regenerated by agentbox: `.devcontainer/devcontainer.json`, `.devcontainer/docker-compose.base.yml`, and `.devcontainer/policy.override.yaml`
- User-owned, never overwritten: `.devcontainer/devcontainer.user.json`, `.devcontainer/docker-compose.user.override.yml`, and `.devcontainer/policy.user.override.yaml`

The managed compose file should carry only agentbox-owned defaults: pinned proxy/agent images, state volumes, workspace mount, read-only policy mounts, and any agent-specific defaults. User mounts and IDE-specific repo mounts should live in the user-owned compose override, following the same ownership logic as `m8.2`.

For policy, do not create a parallel devcontainer-only render implementation. The proxy already knows how to render the effective policy in `m8.3`. The clean extension is to let the devcontainer compose layer mount two extra inputs:

1. `.devcontainer/policy.override.yaml`
2. `.devcontainer/policy.user.override.yaml` (optional)

Then extend `render-policy` to append those layers after the active-agent baseline, shared CLI user policy, and active-agent CLI user policy. The managed devcontainer policy file should only carry agentbox-owned devcontainer defaults, most importantly IDE-related services. That keeps one source of truth for enforcement.

The sharp edge is IDE selection. `switch` is only allowed to ask for the agent, but the current devcontainer init path uses `--ide` to decide mounts, policy services, and JetBrains-specific capabilities. Broadening the managed sidecars to always allow both VS Code and JetBrains would technically avoid extra state, but it also widens permissions and network access for no reason. Recommended direction:

- persist the chosen devcontainer IDE as auxiliary project state when `init --mode devcontainer` runs
- keep `ACTIVE_AGENT` as the only switching identity, but let devcontainer sidecar sync reuse the stored IDE preference
- if the repo has no stored devcontainer IDE metadata, fall back conservatively to the least-privileged layout and make the docs explain how to resync via `agentbox init --mode devcontainer`

For `devcontainer.json`, avoid relying on IDE-native support for a second JSON file. The safer plan is to treat `.devcontainer/devcontainer.user.json` as a user-owned input that agentbox merges into the generated managed `devcontainer.json` during `init` and `switch` sync. That keeps ownership explicit and avoids depending on undocumented editor-specific JSON layering.

`run-compose` and the edit commands need a small devcontainer-sidecar update as well. Even though the IDE owns the devcontainer runtime lifecycle, the CLI still needs to find the correct compose stack and direct edits to the user-owned surfaces. Otherwise `agentbox edit compose` and `agentbox edit policy` will keep teaching users to modify managed files.

### Implementation Steps

- [x] Add devcontainer sidecar path/state helpers, including a minimal place to persist the chosen devcontainer IDE without changing the active-agent identity model
- [x] Replace devcontainer init scaffolding with managed/user sidecar generation and rendered `devcontainer.json` output
- [x] Extend proxy render inputs and devcontainer compose mounts so devcontainer policy uses the same effective-policy path as `m8.3`
- [x] Update `switch` to resync managed devcontainer sidecars for the selected agent while preserving `.devcontainer/*user*` files
- [x] Update compose/path/edit helpers so devcontainer sidecar projects resolve the correct compose stack and user-editable files
- [x] Update docs and targeted BATS coverage for init, switch, edit behavior, compose resolution, and devcontainer regression content

### Resolved Questions

- The stored devcontainer IDE preference and base project name now live in `.agent-sandbox/active-target.env` as auxiliary metadata (`DEVCONTAINER_IDE`, `PROJECT_NAME`), while `ACTIVE_AGENT` remains the only switching identity.
- `devcontainer.user.json` is treated as a user-owned input merged into the generated managed `devcontainer.json` during init/switch sync, keeping the editor-facing file split without depending on IDE-native JSON layering.
- The default policy edit surface for sidecar projects remains `.agent-sandbox/user.policy.yaml`; `.devcontainer/policy.user.override.yaml` is the explicit `--mode devcontainer` override layer.

## Outcome

### Acceptance Verification

- [x] `cli/libexec/init/devcontainer`, `cli/lib/devcontainer.bash`, and the new templates under `cli/templates/devcontainer/` now generate managed sidecars plus user-owned devcontainer extension points instead of copying a single `docker-compose.yml`.
- [x] `cli/lib/run-compose` and `cli/lib/path.bash` now resolve the devcontainer sidecar stack as managed `docker-compose.base.yml` plus optional `docker-compose.user.override.yml`, while still preserving legacy single-file fallback behavior.
- [x] `images/proxy/render-policy` now layers the devcontainer managed/user policy overrides after the active-agent baseline plus shared/agent `.agent-sandbox` policy inputs.
- [x] `cli/libexec/switch/switch` now refreshes devcontainer sidecars alongside layered CLI runtime files, using persisted `DEVCONTAINER_IDE` and `PROJECT_NAME` metadata from `.agent-sandbox/active-target.env`.
- [x] `cli/libexec/edit/compose` now opens `.devcontainer/docker-compose.user.override.yml` for sidecar projects, and `cli/libexec/edit/policy` now treats `.devcontainer/policy.user.override.yaml` as the explicit `--mode devcontainer` edit surface while keeping shared policy edits in `.agent-sandbox/`.
- [x] Targeted verification passed with `cli/support/bats/bin/bats` across `cli/test/init/init.bats`, `cli/test/switch/switch.bats`, `cli/test/compose/run-compose.bats`, `cli/test/path/find_compose_file.bats`, `cli/test/edit/compose.bats`, `cli/test/edit/policy.bats`, and `cli/test/policy/render.bats`.

### Learnings

- Reusing the existing active-target state file for sidecar metadata kept `switch` single-prompt while avoiding lossy inference from managed files.
- Default edit surfaces should continue to point at shared cross-mode policy inputs unless the user explicitly asks for the mode-specific overlay.
- Devcontainer sidecar work is not isolated to init templates; `run-compose`, edit commands, and policy rendering all need to change together or the old managed-file assumptions leak back in.

### Follow-up Items

- `m8.5` still needs legacy-layout detection and clear upgrade guidance for older devcontainer projects that still have single-file `.devcontainer/docker-compose.yml` and flat `policy-devcontainer-<agent>.yaml` files.
- Full yq-backed regression coverage for `cli/test/init/regression.bats` still needs an environment with a real `yq` binary; this container only supported the shell-level suites and stubbed-yq tests.
