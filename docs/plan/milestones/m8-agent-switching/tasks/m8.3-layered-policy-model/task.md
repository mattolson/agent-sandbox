# Task: m8.3 - Layered Policy Model

## Summary

Replace the interim per-agent CLI policy files from `m8.2` with layered shared and agent-specific policy inputs, then make proxy startup/runtime and `agentbox policy render` use the same merge implementation.

## Scope

- Introduce user-owned layered CLI policy files under `.agent-sandbox/`
- Replace CLI reliance on generated `policy-cli-<agent>.yaml` files with runtime merge inputs
- Implement policy merge at proxy startup/runtime for layered CLI workflows
- Add a policy render command that reuses the runtime merge path
- Update CLI policy scaffolding, editing, and switch flows to the layered model
- Keep devcontainer policy sidecar files out of scope for this task; that remains `m8.4`
- Keep explicit legacy-layout guardrails and broader upgrade guidance out of scope for this task; that remains `m8.5`
- Do not add subtract or deny semantics in this task; union-based merge remains the model

## Acceptance Criteria

- [x] `agentbox init --mode cli` creates `.agent-sandbox/user.policy.yaml` plus the active agent's `.agent-sandbox/user.agent.<agent>.policy.yaml` scaffold without overwriting existing user-owned policy files
- [x] `agentbox switch --agent <name>` ensures the target agent's user-owned policy scaffold exists and the next CLI runtime uses shared plus target-agent policy inputs
- [x] Proxy startup/runtime merges the managed active-agent baseline with `.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<agent>.policy.yaml` before enforcement
- [x] `agentbox policy render` outputs the same merged policy content that proxy runtime enforcement uses for the active CLI agent
- [x] `agentbox edit policy` defaults to the shared policy file for layered CLI projects and can target an agent-specific policy file
- [x] Layered CLI compose mounts and proxy startup no longer treat generated `policy-cli-<agent>.yaml` files as the source of truth
- [x] When `m8.2` interim `policy-cli-<agent>.yaml` files are carried forward, they are renamed to a conspicuous deprecated filename so future edits cannot silently target a dead source of truth

## Applicable Learnings

- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place
- The proxy image's baked default policy blocks all outbound traffic, so the selected agent still needs a valid baseline before user overrides are applied
- `run-compose` is the real compatibility boundary for layered CLI flows, so policy commands should follow the same runtime path where possible
- Relative paths in docker-compose files are resolved from the compose file's directory, so any new proxy mounts under `.agent-sandbox/compose/` need explicit path review
- Bash 3.2 compatibility matters in shared CLI helpers, so shell-side path and selection helpers should avoid Bash 4-only features

## Plan

### Files Involved

- `cli/lib/cli-compose.bash` - replace interim `policy-cli-<agent>.yaml` helpers with layered shared and agent policy helpers
- `cli/lib/policyfile.bash` - split flat policy generation from user-owned policy scaffolding and any transitional carry-forward logic
- `cli/libexec/init/cli` - scaffold layered CLI policy files instead of managed flat policy files
- `cli/libexec/init/init` - update review prompts for shared layered policy files
- `cli/libexec/switch/switch` - lazily scaffold target-agent policy files in the layered model
- `cli/libexec/edit/policy` - change layered CLI editing semantics from `policy-<mode>-<agent>.yaml` to shared and agent-specific files
- `cli/libexec/policy/` - new module for `agentbox policy render`
- `cli/templates/compose/base.yml` - mount shared policy input into the proxy and set any runtime render defaults
- `cli/templates/{claude,copilot,codex}/cli/agent.yml` - mount agent-specific policy input and set the active-agent baseline for proxy rendering
- `cli/templates/policy.yaml` or new policy templates - define shared and agent policy scaffold content
- `images/proxy/entrypoint.sh` - render the effective policy before starting mitmdump
- `images/proxy/addons/enforcer.py` - read the rendered policy path via runtime configuration instead of assuming one static source file
- `images/proxy/` new render helper - shared merge implementation for runtime and `policy render`
- `cli/test/edit/policy.bats` - update layered CLI policy editing expectations
- `cli/test/init/policy.bats` - update policy scaffold tests
- `cli/test/init/init.bats` and `cli/test/init/regression.bats` - verify layered policy scaffolding and rendered CLI config
- `cli/test/policy/` - add coverage for `agentbox policy render`
- `docs/policy/schema.md` and `cli/README.md` - document layered policy ownership, merge behavior, and render workflow

### Approach

`m8.2` intentionally shipped an interim policy model: one flat `policy-cli-<agent>.yaml` per active or switched agent, mounted directly into the proxy. That kept switching functional, but it preserved the duplication problem the milestone is trying to eliminate.

`m8.3` should remove that duplication by separating policy concerns into:

- managed baseline: the active agent itself
- user-owned shared additions: `.agent-sandbox/user.policy.yaml`
- user-owned agent-specific additions: `.agent-sandbox/user.agent.<agent>.policy.yaml`

Recommended runtime model:

- The active agent compose layer sets the active agent for the proxy service, for example via an env var such as `AGENTBOX_ACTIVE_AGENT=<agent>`.
- The shared CLI compose base layer mounts `.agent-sandbox/user.policy.yaml` into a fixed proxy path.
- The active agent layer mounts `.agent-sandbox/user.agent.<agent>.policy.yaml` into a fixed proxy path.
- A proxy-side render helper merges:
  1. the managed active-agent baseline
  2. the shared user-owned policy file
  3. the agent-specific user-owned policy file
- The merge result is written to a rendered runtime path and used by the enforcer.

The key design constraint is reuse. `policy render` and runtime enforcement should not maintain separate merge logic. The strongest option is to keep the real merge implementation in the proxy image, then make `agentbox policy render` invoke that same helper through Docker Compose rather than re-implementing merge behavior in shell.

Merge semantics should stay narrow and explicit in this task:

- `services`: union with stable order and de-duplication
- `domains`: union with stable order and de-duplication
- unknown keys: preserve with map deep-merge where feasible rather than silently dropping them

One sequencing problem from `m8.2` needs to be handled deliberately: that task created interim `policy-cli-<agent>.yaml` files. If `m8.3` simply stops using them, current customizations can be stranded. The recommended approach is a targeted carry-forward path when creating layered policy scaffolds:

- if the new user-owned agent policy file is missing but the corresponding interim flat policy exists, compute the delta relative to the current managed agent baseline
- seed only `.agent-sandbox/user.agent.<agent>.policy.yaml` with that remainder
- do not try to infer shared vs agent-specific intent from the old flat file
- rename the old flat file to something conspicuous such as `policy-cli-<agent>.deprecated.yaml` and add a header saying it is no longer read

Deleting the old flat file automatically would be too destructive for a one-time migration path. Renaming keeps recovery possible while making continued edits visibly wrong.

`edit policy` should stop pattern-matching the old flat CLI filenames for layered CLI repos. Recommended behavior:

- no flags: open `.agent-sandbox/user.policy.yaml`
- `--agent <name>`: open `.agent-sandbox/user.agent.<name>.policy.yaml`
- `--mode devcontainer`: preserve the existing flat devcontainer behavior until `m8.4`

### Implementation Steps

- [x] Add layered CLI policy path helpers and user-owned policy scaffold writers
- [x] Update layered CLI compose mounts and proxy runtime env so the proxy can render from shared plus active-agent policy inputs
- [x] Add proxy-side policy render helper and wire proxy startup to use it before enforcer initialization
- [x] Add `agentbox policy render` and make it invoke the same runtime merge path
- [x] Update `init`, `switch`, and `edit policy` to the layered CLI policy model, including one-time carry-forward from interim `policy-cli-<agent>.yaml` files and post-migration rename to deprecated filenames
- [x] Update docs and targeted tests for policy scaffolding, render behavior, and layered CLI editing

### Resolved Questions

- `policy render` was implemented as a new `policy/` module (`agentbox policy render`) while editing remained under `edit policy`, which kept runtime inspection separate from editor workflows.
- Unknown policy keys now deep-merge when both layers provide mappings. `services` and `domains` remain explicit union cases, while other lists and scalars use later-layer replacement.

## Outcome

### Acceptance Verification

- [x] `cli/lib/cli-compose.bash` now scaffolds `.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<agent>.policy.yaml`, preserves existing user-owned files, and upgrades active managed compose layers to mount those files instead of the interim flat policy file.
- [x] `cli/libexec/switch/switch` still switches agents, but layered CLI projects now treat the command as an idempotent runtime-file ensure path as well, so target-agent policy scaffolds and managed compose wiring stay current even on same-agent refreshes.
- [x] `images/proxy/render-policy`, `images/proxy/entrypoint.sh`, and `images/proxy/addons/enforcer.py` now render the effective policy before mitmproxy starts and enforce from the rendered path via `POLICY_PATH`.
- [x] `cli/libexec/policy/render` runs the proxy-side render helper through the layered Compose stack, so inspection and enforcement share one merge implementation.
- [x] `cli/libexec/edit/policy` now defaults layered CLI projects to `.agent-sandbox/user.policy.yaml`, supports `--agent <name>` for `.agent-sandbox/user.agent.<name>.policy.yaml`, and skips misleading proxy restarts when editing an inactive agent's file.
- [x] `cli/lib/policyfile.bash` carries forward interim `policy-cli-<agent>.yaml` content into the new agent-specific user-owned file, removes the managed baseline service from that carried-forward copy, and renames the old file to `policy-cli-<agent>.deprecated*.yaml`.
- [x] Full verification now passed with `cli/support/bats/bin/bats` across the `m8.3` suite, including `cli/test/policy/render.bats`, `cli/test/edit/policy.bats`, `cli/test/compose/run-compose.bats`, `cli/test/init/init.bats`, `cli/test/init/policy.bats`, `cli/test/init/regression.bats`, and `cli/test/switch/switch.bats`.

### Learnings

- Reusing the proxy-side merge implementation for both runtime and `agentbox policy render` kept the ownership model clean and avoided creating a second YAML merge contract in shell.
- `run-compose` is the practical upgrade boundary for layered CLI mode. Ensuring active-agent runtime files there keeps existing managed layers current without forcing users to rerun `init`.
- Restart behavior for layered policy editing needs to respect which agent is active. Restarting the current proxy after editing an inactive agent's file would imply the change had taken effect when it had not.

### Follow-up Items

- `m8.4` will need to add the devcontainer-side policy override layer and decide how it plugs into the same render path.
- `m8.5` will still need explicit guardrails and upgrade messaging for older flat policy layouts beyond the narrow `m8.2` carry-forward path.
