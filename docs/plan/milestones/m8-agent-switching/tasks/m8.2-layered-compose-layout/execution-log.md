# Execution Log: m8.2 - Layered Compose Layout

## 2026-03-11 23:29 UTC - Execution started

Execution approved. The implementation will treat the CLI compose layer set as the source of truth and update all CLI consumers that currently assume `.agent-sandbox/docker-compose.yml` exists.

**Decision:** Carry the baseline CLI policy dependency in `m8.2` by scaffolding per-agent CLI policy files until `m8.3` replaces them with shared plus agent-specific policy layering.

**Decision:** Do not pre-generate managed layers for every supported agent during `init`. That would force unnecessary image pulls and interacts badly with the current single `AGENTBOX_AGENT_IMAGE` override. Instead, CLI init creates the active agent's managed files, and `switch` lazily scaffolds missing target-agent files with the default image for that agent.

## 2026-03-11 23:58 UTC - Runtime consumers migrated

Replaced the single-file CLI compose assumption with layered resolution in `cli/lib/run-compose`, backed by the new `cli/lib/cli-compose.bash` helper. Layered CLI projects now resolve `base.yml`, `agent.<active>.yml`, `user.override.yml`, and `user.agent.<active>.override.yml` in deterministic order.

Updated `cli/libexec/init/cli` to generate layered CLI files and `cli/libexec/init/init` to review the generated policy plus shared override instead of a managed compose file. `cli/libexec/edit/compose` now opens the shared override for layered CLI projects, `cli/libexec/bump/bump` updates the managed base plus initialized agent layers, and `cli/libexec/switch/switch` lazily scaffolds missing target-agent files before flipping `active-target.env`.

**Learning:** `run-compose` is the real compatibility boundary. Once it understands layered CLI stacks, `exec`, `destroy`, `edit policy`, `up`, `down`, and `logs` follow the new layout automatically.

## 2026-03-12 00:07 UTC - Verification complete

Added focused BATS coverage for layered compose path emission, runtime compose ordering, layered `edit compose` behavior, updated `init` prompts, and `switch` lazy scaffolding. The suites that passed were:

- `cli/test/path/path.bats`
- `cli/test/compose/run-compose.bats`
- `cli/test/edit/compose.bats`
- `cli/test/init/init.bats`
- `cli/test/switch/switch.bats`

The container still lacks the real `yq` binary, and GitHub release asset downloads were blocked with proxy `403`, so I could not run the repo's existing `yq`-dependent suites directly. To close the highest-risk gaps anyway, I used temporary local smoke scripts with a non-committed `yq` shim to exercise the actual layered CLI init, switch, and bump flows end to end.

## 2026-03-11 22:59 UTC - Planning complete

Reviewed the `m8` milestone, the updated switching decision, `docs/plan/learnings.md`, the completed `m8.1` task, and the current CLI compose implementation in `cli/lib/path.bash`, `cli/lib/run-compose`, `cli/lib/composefile.bash`, `cli/libexec/init/cli`, `cli/libexec/edit/compose`, `cli/libexec/bump/bump`, and the related BATS suites.

The main planning conclusion is that `m8.2` is broader than the milestone bullet makes it sound. The current CLI assumes one generated compose file in `.agent-sandbox/docker-compose.yml`, and that assumption is embedded in runtime execution, edit flows, bump logic, destroy behavior, and regression tests. A safe layer refactor therefore has to update the whole CLI compose surface, not just `init`.

**Issue:** The milestone separates compose layering (`m8.2`) from policy layering (`m8.3`), but once CLI runtime selection follows `active-target.env`, the newly selected agent still needs a valid baseline policy immediately.
**Solution:** Plan `m8.2` around an interim baseline-per-agent CLI policy setup so switching works before shared/agent policy merge lands in `m8.3`.

**Decision:** Treat user customization mounts as user-owned override content, not managed layer content. The current `customize_compose_file()` model cannot be carried forward unchanged because it writes user choices directly into generated files.

**Learning:** Moving the CLI compose files from `.agent-sandbox/` to `.agent-sandbox/compose/` changes all repo-relative mount paths. That is a correctness risk, not just a cosmetic path change.
