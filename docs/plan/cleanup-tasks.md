# Cleanup Tasks

Misc small issues to be tracked. Items are grouped by priority and can be addressed across multiple PRs.

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

- [x] **Dead code in `cli/lib/select.bash`.** `select_multiple()` (line 52) and `read_multiline()` (line 84) are defined but never called.

- [x] **Variable ordering in `cli/lib/require.bash`.** `exitcode_expectation_failed` is defined at line 19, after the `require()` function that references it at line 18. Should be defined first.

- [x] **Fallback scripts use `sh` instead of `bash`.** `cli/libexec/compose/_` and `cli/libexec/exec/_` use `#!/bin/sh` while everything else uses `#!/usr/bin/env bash`.

## Worth Discussing

Design decisions that may or may not need action.

- [ ] **Templates are non-functional without `agentbox init`.** Neither CLI nor devcontainer templates include a policy volume mount on the proxy service. `customize_compose_file()` adds it dynamically. If someone copies a template manually, the proxy starts in enforce mode with no policy and exits. Consider adding a placeholder mount or documenting this.

- [x] **Devcontainer templates mount `.devcontainer` as read-only (line 41) but the directory only exists because init just created it.** Fix: added comments clarifying that paths are relative to the compose file's directory (`.devcontainer/`).

- [ ] **Copilot devcontainer.json has empty JetBrains plugins array.** Should look into installing the [copilot plugin](https://plugins.jetbrains.com/plugin/17718-github-copilot--your-ai-pair-programmer)

## Enhancements

- [ ] **`agentbox init` should accept all defaults without prompting.** The default mode should run through the entire init process in one step using defaults (agent=claude, mode=cli) with no interactive prompts. Add `--interactive` flag to enable the current flow where each option is presented for selection. Also support passing options directly as flags so users can override specific defaults without going interactive. Proposed flags:
  - `--agent <name>` (default: claude)
  - `--mode <mode>` (default: cli)
  - `--ide <ide>` (default: none for cli, vscode for devcontainer)
  - `--path <dir>` (default: current directory)
  - `--name <name>` (default: derived from directory name via `derive_project_name`)
  - `--proxy-image <image>` (default: latest proxy)
  - `--agent-image <image>` (default: latest agent image for selected agent)
  - `--interactive` (enable interactive prompts for all options)
  The `customize_compose_file` function already skips prompts when env vars are pre-set (`proxy_image`, `agent_image`, `mount_claude_config`, `enable_shell_customizations`, `enable_dotfiles`, `mount_git_readonly`, `mount_idea_readonly`, `mount_vscode_readonly`). The init function needs to parse flags, set defaults for everything, and only call interactive prompts when `--interactive` is passed.

- [ ] **Audit CLI test coverage.** Review every module and library file for test coverage gaps. Known gaps from initial review:
  - `cli/bin/agentbox` - main dispatcher has no tests (command resolution, PATH manipulation, fallback handling)
  - `cli/libexec/exec/exec` - no tests
  - `cli/libexec/version/version` - no tests
  - `cli/libexec/init/policy` - no direct unit tests (only tested indirectly via init regression tests)
  - `cli/lib/logging.bash` - no tests
  - `cli/lib/select.bash` - no tests for `select_option`, `select_yes_no`, `read_line`, `open_editor`
  - `cli/lib/composefile.bash` - `pull_and_pin_image` Docker error paths untested, `set_project_name` untested
  - `cli/libexec/bump/bump` - `bump_service` tested but top-level `bump` command untested
  - `cli/libexec/edit/compose` - editor integration untested beyond mtime check
  - `cli/libexec/edit/policy` - proxy restart path only partially tested
  Run `cli/run-tests.bash --coverage` (requires kcov) to get a baseline coverage report, then fill gaps.

- [x] **Move `agentbox compose bump` to `agentbox bump`.** Promoted to top-level command. Also reorganized `compose edit` to `edit compose`, `policy` to `edit policy`, and added docker compose fallthrough for unrecognized commands.

- [x] **Restructure proxy commands.** Moved `agentbox policy` to `agentbox edit policy`. Docker compose passthrough handles `agentbox logs proxy` directly.

- [x] **Reorganize README and extract optional feature docs.** The README is 350+ lines and mixes essential setup with optional features. Proposed structure:
  - **README.md** (keep short): What it does, Supported agents, Quick start, Network policy overview, Security, Contributing, License
  - **docs/git.md**: Git configuration (git from host vs container, credential setup, SSH blocking)
  - **docs/dotfiles.md**: Dotfiles support and shell customization (merge the two sections)
  - **docs/stacks.md**: Extending with language stacks
  - **docs/images.md**: Image versioning, building custom images
  Each extracted section gets a one-line summary and link in the README.

- [x] **README git credential instructions reference `gh` which is no longer installed by default.** The "Git from container" section (lines 227-245) tells users to run `gh auth login` and references the gh CLI for credential setup. The security section (line 318) also references `gh auth login`. These need to be updated to reflect that `gh` is not in the base image. Options: document how to install it via a language stack or custom Dockerfile, or provide alternative credential setup instructions (e.g., git credential store with a PAT).

- [x] **Make `agentbox exec` safe for multiple terminal sessions.** Currently runs `docker compose up -d` every time, which is a no-op when containers are already running with the same config. But if the compose file has changed (e.g., after `agentbox bump`), `up -d` will recreate containers and kill existing sessions. Fix: check if the agent container is already running first, only run `up -d` if it isn't. Something like `docker compose ps --status running --quiet agent` to detect a running container before deciding whether to start.

- [x] **Review container capability grants.** Audited all capabilities. All are justified and minimal. Added per-capability comments to all compose templates and the JetBrains capability function. Proxy `DAC_OVERRIDE` could be eliminated by switching to `USER mitmproxy` in the proxy Dockerfile (future improvement). Agent `SETUID`/`SETGID` could be eliminated by switching to a root entrypoint with gosu (marginal gain, current sudoers approach is standard).

- [ ] **Auto-configure git identity from repo history.** Users with a global gitconfig on the host don't have it available inside the container, so commits fail until `user.name` and `user.email` are set. At container startup, if git identity isn't configured in the repo, extract the most recent commit's author name and email from the log and set them as repo-level config (`.git/config`). This is safe because `.git/config` isn't tracked and the values match what the user already committed with. Edge cases: last commit from a collaborator, multiple identities, empty repos. For those, the dotfiles mount (`.gitconfig`) is the escape hatch.

- [ ] **Simplify compose project name for CLI mode.** `derive_project_name()` in `cli/lib/path.bash` currently produces `{dir}-sandbox-{mode}` for both modes. For CLI mode, drop the mode suffix so it's just `{dir}-sandbox`. Keep `{dir}-sandbox-devcontainer` for devcontainer mode to distinguish the two when both exist in the same project. The CLI init caller at `cli/libexec/init/cli:61` passes `"cli"` and devcontainer init at `cli/libexec/init/devcontainer:65` passes `"devcontainer"`.
