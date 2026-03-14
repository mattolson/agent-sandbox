# Execution Log: m8.4 - Devcontainer Sidecar Files

## 2026-03-13 06:07 UTC - Managed devcontainer compose file renamed to `docker-compose.base.yml`

Follow-up refinement after implementation review: the managed devcontainer sidecar file was renamed from
`docker-compose.override.yml` to `docker-compose.base.yml`.

**Issue:** Calling the managed file an "override" was misleading. In the new sidecar layout it is the base managed
layer, while `docker-compose.user.override.yml` is the actual user-owned override layer.
**Solution:** Renamed the managed file across helpers, templates, tests, docs, and planning artifacts so the naming now
matches the role.

**Decision:** Keep `docker-compose.user.override.yml` unchanged. The base/override pairing is clearer than managed
override/user override.

## 2026-03-13 05:45 UTC - Targeted verification passed

Completed the shell-level verification pass for the new devcontainer sidecar flow.

Passed suites:

- `cli/test/init/init.bats`
- `cli/test/switch/switch.bats`
- `cli/test/compose/run-compose.bats`
- `cli/test/path/find_compose_file.bats`
- `cli/test/edit/compose.bats`
- `cli/test/edit/policy.bats`
- `cli/test/policy/render.bats`

**Issue:** The full init regression suite still depends on a real `yq` binary, and this container does not have one installed.
**Solution:** Verified the shell-level control flow with the targeted BATS suites above and recorded the remaining regression gap explicitly in the task outcome and follow-up notes.

**Learning:** The sidecar change touched enough command surfaces that the targeted shell suites gave more signal than a narrower init-only check would have.

## 2026-03-13 05:32 UTC - Devcontainer sidecar model implemented

Replaced the old single-file devcontainer init path with a managed/user-owned sidecar layout and wired it through state, switch, compose resolution, policy rendering, and docs.

Key implementation changes:

1. Added `cli/lib/devcontainer.bash` to own devcontainer sidecar paths, scaffolding, metadata-aware sync, and render behavior.
2. Extended `.agent-sandbox/active-target.env` to persist `DEVCONTAINER_IDE` and `PROJECT_NAME`, while keeping `ACTIVE_AGENT` as the switching identity.
3. Switched devcontainer templates to managed `docker-compose.base.yml` plus shared user-owned `.devcontainer/*user*` files, and rendered `devcontainer.json` from the agent template plus `devcontainer.user.json`.
4. Updated `run-compose`, `find_compose_file`, `edit compose`, `edit policy`, and `switch` to respect the new devcontainer sidecar layout.
5. Extended `images/proxy/render-policy` so devcontainer managed/user policy overrides layer onto the same `.agent-sandbox` shared/agent policy inputs introduced in `m8.3`.

**Issue:** The original plan treated devcontainer policy editing as if it should default to a `.devcontainer` file. In practice, that would have made the devcontainer-only override look like the main policy surface and hidden the shared `.agent-sandbox` policy that still applies in both modes.
**Solution:** Kept the default `agentbox edit policy` target on `.agent-sandbox/user.policy.yaml` and made `.devcontainer/policy.user.override.yaml` the explicit `--mode devcontainer` surface.

**Decision:** Store the devcontainer IDE and project name in the existing active-target state file instead of creating another managed metadata file. That let `switch` remain a one-question command while keeping sidecar sync deterministic.

**Decision:** Treat `.devcontainer/devcontainer.user.json` as agentbox-merged input, not an IDE-native second config file. That avoids relying on editor-specific JSON layering support.

## 2026-03-13 04:59 UTC - Planning complete

Reviewed the `m8` milestone, `docs/plan/learnings.md`, decision `004`, the completed `m8.2` and `m8.3` task docs, the current devcontainer init path, the switch command, compose/path helpers, edit flows, templates, and regression tests.

**Issue:** The repository still treats devcontainer setup as a single managed scaffold (`.devcontainer/docker-compose.yml` plus `.agent-sandbox/policy-devcontainer-<agent>.yaml`), which conflicts with the milestone's managed-vs-user-owned sidecar model.
**Solution:** Plan `m8.4` around explicit managed `.devcontainer` sidecars plus protected `.devcontainer/*user*` extension points, with the proxy render path extended rather than duplicated.

**Issue:** `agentbox switch` is only allowed to ask for the agent, but current devcontainer generation still depends on an IDE choice for capabilities, mounts, and policy services.
**Solution:** Recommended preserving the chosen IDE as auxiliary project state so managed devcontainer sidecars can be resynced without widening permissions or prompting for unrelated input during `switch`.

**Decision:** Reuse the proxy-side policy render path from `m8.3` for devcontainer overrides instead of reviving a separate flat `policy-devcontainer-<agent>.yaml` source of truth.

**Decision:** Treat `.devcontainer/devcontainer.user.json` as user-owned input merged into the generated managed `devcontainer.json` during sync, rather than assuming IDE-native support for split devcontainer JSON files.

**Learning:** The devcontainer sidecar work is not just templating. It also touches compose stack resolution, safe edit surfaces, and state persistence if the managed-vs-user-owned contract is going to hold end to end.
