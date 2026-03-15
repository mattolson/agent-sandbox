# Execution Log: m8.6 - Legacy Guardrails + Docs/Tests

## 2026-03-15 01:10 UTC - Real-environment regression verification closed the remaining init gap

Host-side verification with real `docker` and `yq` closed the last open `m8.6` gap in `cli/test/init/regression.bats`, but it exposed a few portability assumptions in the rewritten helpers first.

**Issue:** The first regression-helper pass overfit this environment in three ways:

- the new legacy-layout helper used `mapfile` without sourcing `compat.bash`, which broke on macOS Bash 3.2
- BATS `run` does not interpret shell-style `VAR=value cmd` assignments, so helper queries that tried that form failed before reaching `yq`
- `docker compose config --no-interpolate` plus `yq` did not render one stable YAML shape; environment entries appeared as maps or `KEY=value` sequences, and volume entries appeared as normalized mount objects or raw strings

**Solution:** Source the existing Bash 3.2 shim in `cli/lib/legacy-layout.bash`, change BATS helper calls to `run env VAR=value ...`, and rewrite the init-regression assertion helpers to check semantic invariants in Bash rather than depend on `endswith(...)` or one rendered node shape.

**Decision:** Keep the effective rendered-compose regression strategy. The portability fix is to normalize helper assertions, not to fall back to brittle raw-file assertions again.

**Learning:** When regression tests consume rendered compose output from real tooling, the helper layer has to normalize cross-version representation differences. Assert on meaning, not one exact YAML shape.

## 2026-03-14 19:24 UTC - Removed the unpublished `policy-cli` compatibility exception

Dropped the last `m8.3` carry-forward behavior for `policy-cli-<agent>.yaml` after confirming that no `m8` work has shipped publicly.

**Issue:** Treating `policy-cli-<agent>.yaml` as a supported special case inside layered repos kept a private transitional branch alive in the public behavior and documentation. That weakened the upgrade story for little real user value.

**Solution:** Treat `policy-cli-<agent>.yaml` the same way as the other single-file legacy artifacts: fail fast, tell the user to rename it to `*.legacy.*`, rerun `init`, and copy customizations into the layered user-owned policy files.

**Decision:** Remove the migration helper path entirely instead of just hiding it behind the new guardrail. The simpler product rule is that all `policy-cli-<agent>.yaml` files are legacy.

## 2026-03-14 19:24 UTC - Implementation complete with one local verification gap

Implemented the legacy guardrail and upgrade-doc story end to end:

- added `cli/lib/legacy-layout.bash` to detect unsupported pre-`m8` single-file layouts, format rename-and-rerun guidance, and point to a dedicated upgrade guide
- wired that guard into `init`, `switch`, runtime compose execution, `edit compose`, `edit policy`, and `bump`
- kept `destroy` on its existing cleanup-oriented path instead of forcing the guardrail into the one command that can still help remove old scaffolds
- rewrote `cli/test/init/regression.bats` around effective `docker compose config --no-interpolate` output and minimal raw-file checks
- added `docs/upgrades/m8-layered-layout.md` plus README, CLI, and policy-schema updates

**Issue:** Both `run-compose` and `bump` originally still called `require docker` before the new legacy-layout guard. That masked the intended failure mode and caused the first regression runs to report `docker required` instead of upgrade guidance.

**Solution:** Move the legacy-layout check ahead of tool availability checks in those paths so users on unsupported legacy layouts see the actionable upgrade error first.

**Decision:** Keep `destroy` as the cleanup exception and remove dead legacy-edit fallback code from `edit policy` instead of keeping two contradictory upgrade stories alive in the same command.

**Learning:** When a command change introduces a new primary failure mode, verification needs to cover ordering, not just message text. Guardrails that run after dependency checks are effectively invisible.

## 2026-03-14 17:44 UTC - Planning completed

Reviewed the `m8` milestone, `docs/plan/learnings.md`, decision `004`, and the completed `m8.1` through `m8.5` task records, then inspected the current runtime helpers, edit flows, docs, and BATS coverage around compose and policy path resolution.

The main planning conclusion is that `m8.6` should not just delete legacy fallback code wholesale. The current repository uses legacy path handling for two different reasons:

- some commands still silently operate on unsupported pre-m8 single-file layouts
- some cleanup-oriented flows, especially `destroy`, still benefit from being able to resolve an old layout

**Issue:** Legacy behavior is currently spread across `find_compose_file`, `run-compose`, `edit compose`, `edit policy`, `bump`, `destroy`, and their corresponding tests. Removing fallback in the wrong layer would either leave silent support in place or break the one cleanup path users still have.

**Solution:** Plan around an explicit legacy-layout detector plus shared upgrade guidance, then invoke it from the user-facing commands that should now require layered layouts. Treat `destroy` as a deliberate exception unless implementation shows that is unsafe.

**Decision:** Treat `policy-cli-<agent>.yaml` as legacy layout rather than preserving a special transitional path, because the unpublished `m8` work does not justify a permanent compatibility branch.

**Learning:** Effective rendered-compose assertions are now the right regression target for layout work. Raw file checks still matter, but only for ownership and scaffolding details that merged compose output cannot express.

## 2026-03-14 17:44 UTC - Planning refinement after user feedback

Refined the documentation part of the plan after user feedback on the upgrade experience. The error message should not try to fully explain the `m8` layout shift inline.

**Decision:** Add a dedicated upgrade guide markdown document and have legacy-layout errors point to it after the short actionable steps. The guide should explain the layout change introduced in `m8`, but it should be framed as a user upgrade document, not as an internal milestone changelog.

**Decision:** The preferred upgrade flow is now: rename legacy generated files to a conspicuous `*.legacy.*` form, rerun `agentbox init` for the intended mode and agent, then manually copy customizations into the new user-owned layered files.
