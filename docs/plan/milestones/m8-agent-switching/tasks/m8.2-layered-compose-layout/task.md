# Task: m8.2 - Layered Compose Layout

## Summary

Replace the CLI mode single-file compose layout with explicit managed and user-owned layers, then update the CLI backend to resolve the effective compose stack from the active agent in deterministic order.

## Scope

- Refactor CLI `init` to generate managed compose layers under `.agent-sandbox/compose/`
- Introduce a deterministic CLI merge order: base, active-agent managed layer, shared user override, optional active-agent user override
- Preserve ownership boundaries: managed files are rewritten by agentbox, user-owned override files are never overwritten
- Move optional user customizations out of managed compose generation and into user-owned override scaffolds
- Update CLI compose consumers (`run-compose`, `edit compose`, `bump`, and commands that depend on them) to work with the layered layout
- Keep devcontainer compose generation unchanged in this task; devcontainer sidecars remain `m8.4`
- Keep shared/agent policy merge semantics out of this task; that remains `m8.3`
- Keep legacy-layout detection and upgrade guidance out of this task; that remains `m8.5`
- Do not expand the `switch` command surface beyond what is needed for the CLI backend to follow the active agent

## Acceptance Criteria

- [ ] `agentbox init --mode cli` creates `.agent-sandbox/compose/base.yml`, the active agent's managed CLI layer, and the shared/user override scaffolds without rewriting existing user-owned overrides
- [ ] `agentbox init --mode cli` creates user-owned compose override scaffold files when missing and does not overwrite existing user-owned override files on re-init
- [ ] CLI runtime commands resolve compose files in deterministic order based on `active-target.env`: base, active agent, shared override, optional active-agent override
- [ ] `agentbox switch --agent <name>` changes which CLI compose layer set is used on the next CLI runtime command and lazily scaffolds missing target-agent managed files when needed
- [ ] `agentbox edit compose` points users at a user-owned override file rather than a managed compose layer
- [ ] `agentbox bump` updates managed CLI compose layers without modifying user-owned override files

## Applicable Learnings

- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place
- Relative paths in docker-compose files are resolved from the compose file's directory, not the repo root; moving CLI files into `.agent-sandbox/compose/` changes every repo-relative mount path
- Devcontainer and compose flows use different files and ownership rules, so the CLI layout refactor should stay isolated from devcontainer sidecars
- The proxy image's baked default policy blocks all outbound traffic, so CLI switching cannot rely on image defaults alone while policy layering is still deferred to `m8.3`
- Bash 3.2 compatibility matters in shared CLI helpers, so file-list helpers should avoid Bash 4-only features

## Plan

### Files Involved

- `cli/lib/agent.bash` - reuse active-agent state and likely add helper(s) for iterating supported agents
- `cli/lib/path.bash` - replace single-file CLI compose discovery with layered compose path helpers
- `cli/lib/run-compose` - build `docker compose` arguments from the active CLI layer set
- `cli/lib/composefile.bash` - split managed-layer generation from user override scaffolding and update relative mount paths for `.agent-sandbox/compose/`
- `cli/libexec/init/cli` - generate managed CLI layers and user override scaffolds instead of a single `.agent-sandbox/docker-compose.yml`
- `cli/libexec/init/init` - update CLI review prompts to point at the correct user-editable file(s)
- `cli/libexec/init/policy` - factor the policy writer so CLI init and `switch` can scaffold baseline CLI policy files on demand until `m8.3`
- `cli/libexec/edit/compose` - open a user-owned override file instead of a managed layer
- `cli/libexec/bump/bump` - update managed base and agent layers instead of a single compose file
- `cli/test/path/find_compose_file.bats` - replace or extend for layered CLI compose path resolution
- `cli/test/compose/compose.bats` - verify `run-compose` passes the expected `-f` stack in the right order
- `cli/test/edit/compose.bats` - update expectations for editing user-owned override files
- `cli/test/bump/bump.bats` and `cli/test/bump/bump_service.bats` - update for managed layered files
- `cli/test/init/init.bats` and `cli/test/init/regression.bats` - verify scaffolding and effective CLI config under the new layout
- `cli/README.md` - document layered CLI compose ownership and editing behavior
- `cli/templates/...` - add new CLI layer templates and override scaffolds

### Approach

The current CLI layout couples three concerns into one generated file:

1. managed runtime defaults
2. pinned image references
3. user-specific customizations such as dotfiles, `.git`, and Claude config mounts

That coupling is the root problem. `m8.2` should separate those concerns instead of trying to keep a compatibility shim around the old `.agent-sandbox/docker-compose.yml`.

Recommended structure:

- Managed:
  - `.agent-sandbox/compose/base.yml`
  - `.agent-sandbox/compose/agent.<agent>.yml`
- User-owned:
  - `.agent-sandbox/compose/user.override.yml`
  - `.agent-sandbox/compose/user.agent.<agent>.override.yml` when needed

Implementation should treat CLI compose layers as the source of truth and make `run-compose` responsible for assembling the final `docker compose -f ... -f ...` stack from the active agent. That keeps all CLI commands consistent because `up`, `down`, `logs`, `compose`, `exec`, `destroy`, `edit policy`, and `switch` already funnel through `run-compose` either directly or indirectly.

The current `composefile.bash` helpers should be split conceptually into:

- managed-layer writers
  - project name in base layer
  - pinned proxy image in base layer
  - pinned agent image and agent-specific volumes/env in agent layer
  - agent-specific proxy policy mount in agent layer
- user-override scaffold writers
  - shared mounts: shell customizations, dotfiles, `.git`, `.idea`, `.vscode`
  - agent-specific mounts: Claude config
  - activation from existing `AGENTBOX_*` env vars should write into user-owned override files, not managed layers

One sequencing issue needs to be handled explicitly: once the CLI backend starts following `active-target.env`, the selected agent must have a valid baseline policy before `m8.3` lands. The proxy image default policy is `services: []`, which blocks all outbound traffic. The chosen interim approach is to generate the active agent's baseline CLI policy during CLI init and lazily scaffold additional per-agent baseline policy files during `switch`. `m8.3` can then replace that baseline-per-agent model with shared plus agent-specific policy layering.

`edit compose` should stop opening a managed file. The recommended m8.2 behavior is to open `.agent-sandbox/compose/user.override.yml` by default, because that is the stable shared customization point. Agent-specific override editing can remain manual for now unless the implementation reveals a strong need for an agent-aware flag.

`bump` should update the managed base layer plus any initialized agent layers, not just the active one. Missing agent layers should stay lazy; they will be created on first switch to that agent.

### Implementation Steps

- [ ] Add layered CLI compose path helpers and `run-compose` merge-order logic based on the active agent
- [ ] Add managed CLI compose templates/layer generators and remove the single-file CLI generator
- [ ] Move optional customization scaffolding into user-owned override files while preserving existing `AGENTBOX_*` init behavior
- [ ] Scaffold baseline CLI policy files for the active agent at init time and lazily for additional agents during `switch` so switching remains functional before `m8.3`
- [ ] Update `edit compose`, `bump`, and affected CLI tests for the layered layout
- [ ] Run targeted BATS coverage for path resolution, compose command assembly, init scaffolding, edit, and bump

### Open Questions

- Should `m8.2` pull a limited amount of CLI regression coverage forward to rendered effective config, even though the broader regression conversion is listed under `m8.5`? Recommended: yes, for the CLI cases directly broken by removing `.agent-sandbox/docker-compose.yml`.
- Should `edit compose` remain shared-only in this task, or grow agent-aware selection now? Recommended: shared-only in `m8.2`; keep the command surface small until actual user friction appears.

## Outcome

### Acceptance Verification

- [x] `agentbox init --mode cli` now writes `.agent-sandbox/compose/base.yml`, the active agent managed layer, `.agent-sandbox/compose/user.override.yml`, and the active agent override scaffold without overwriting existing user-owned overrides.
- [x] CLI runtime commands now resolve the effective compose stack in deterministic order via `run-compose`: base, active agent, shared override, optional active-agent override.
- [x] `agentbox switch --agent <name>` now lazily scaffolds missing target-agent managed files for layered CLI projects before updating `active-target.env`.
- [x] `agentbox edit compose` now opens `.agent-sandbox/compose/user.override.yml` for layered CLI projects.
- [x] `agentbox bump` now updates the managed base layer plus any initialized managed agent layers without touching user-owned overrides.
- [x] Targeted verification completed with BATS coverage for path/runtime resolution, edit/init/switch behavior, plus smoke coverage for layered CLI init, switch, and bump using a temporary local `yq` shim because the real binary was unavailable in this container.

### Learnings

- Eagerly generating every supported agent layer during `init` looks simpler on paper, but it couples the design to unnecessary image pulls and to the current single `AGENTBOX_AGENT_IMAGE` override. Lazy scaffolding on `switch` is the safer fit for the existing CLI surface.
- The layered migration is only trustworthy once `run-compose` becomes the single source of compose-stack assembly. Updating `init` alone would have left `edit`, `exec`, `destroy`, and `edit policy` on the old single-file assumption.

### Follow-up Items

- `m8.3` will need to replace the interim per-agent baseline CLI policy files with the shared plus agent-specific merge model.
- `m8.4` will need to mirror the ownership model into `.devcontainer/` sidecar files without reintroducing single-file CLI assumptions.
