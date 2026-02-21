# Post-CLI Merge Cleanup

Tracking issues identified after merging the `agentbox` CLI and related changes from jakub-bochenski. Items are grouped by priority and can be addressed across multiple PRs.

## Broken

These are functionally broken or point to things that no longer exist.

- [x] **`.env` references deleted path.** `COMPOSE_FILE=.devcontainer/docker-compose.yml` but `.devcontainer/` was removed. Fix: deleted `.env`.

- [x] **`docs/policy/schema.md` has dead links (lines 82-83).** Links to `../claude/.devcontainer/policy.yaml` and `../copilot/.devcontainer/policy.yaml` which do not exist. Fix: replaced with reference to `cli/templates/policy.yaml`.

- [x] **`docs/policy/schema.md` copilot service definition is wrong.** Documents 5 domains for the `copilot` service. `enforcer.py` defines 12. Fix: updated to match enforcer.py.

- [x] **CHANGELOG references non-existent policy example files (lines 41-42).** `docs/policy/examples/claude.yaml` and `docs/policy/examples/claude-devcontainer.yaml` were never created. Fix: replaced with `agentbox init` workflow description.

- [x] **CHANGELOG mentions `PROXY_MODE=discovery` (line 58).** This mode does not exist in `enforcer.py`. Only `enforce` and `log` are supported. Fix: changed to `PROXY_MODE=log`.

## Stale Documentation

These are not broken but describe the old architecture and will confuse anyone reading them.

- [x] **`.claude/CLAUDE.md` references `.devcontainer/` throughout.** Fix: full refresh of CLAUDE.md with current paths, service listings, and architecture description.

- [x] **`README.md` template paths are wrong (lines 26-27).** References `templates/claude/` and `templates/copilot/`. Fix: changed to `cli/templates/claude/` and `cli/templates/copilot/`.

- [x] **`docs/policy/schema.md` line 76 references `.devcontainer/` mount.** Fix: updated to mention both `.agent-sandbox/` (CLI mode) and `.devcontainer/` (devcontainer mode).

- [x] **No CHANGELOG entry for the CLI.** Fix: added full `[Unreleased]` section covering CLI commands, Docker distribution, Copilot support, JetBrains support, image pinning, Bash 3.2 compatibility.

- [x] **CHANGELOG v0.3.0 breaking change describes old policy workflow (lines 38-44).** Fix: replaced with `agentbox init` workflow description.

## Code Cleanup

Minor issues in the CLI codebase.

- [ ] **Dead code in `cli/lib/select.bash`.** `select_multiple()` (line 52) and `read_multiline()` (line 84) are defined but never called.

- [ ] **Variable ordering in `cli/lib/require.bash`.** `exitcode_expectation_failed` is defined at line 19, after the `require()` function that references it at line 18. Should be defined first.

- [ ] **Fallback scripts use `sh` instead of `bash`.** `cli/libexec/compose/_` and `cli/libexec/exec/_` use `#!/bin/sh` while everything else uses `#!/usr/bin/env bash`.

## Worth Discussing

Design decisions that may or may not need action.

- [ ] **Templates are non-functional without `agentbox init`.** Neither CLI nor devcontainer templates include a policy volume mount on the proxy service. `customize_compose_file()` adds it dynamically. If someone copies a template manually, the proxy starts in enforce mode with no policy and exits. Consider adding a placeholder mount or documenting this.

- [x] **Devcontainer templates mount `.devcontainer` as read-only (line 41) but the directory only exists because init just created it.** Fix: added comments clarifying that paths are relative to the compose file's directory (`.devcontainer/`).

- [x] **Copilot devcontainer.json has empty JetBrains plugins array.** Confirmed intentional: no Copilot JetBrains plugin exists.
