# m5-cli

**Status: Complete**

The `agentbox` CLI for initializing, managing, and operating sandboxed agent environments.

## Goal

Give developers a single command-line tool that handles the full lifecycle of an agent sandbox: scaffolding config files, editing policy, executing commands in containers, updating images, and tearing down environments. The CLI should work for both CLI-mode (standalone Docker Compose) and devcontainer-mode (VS Code / JetBrains) users, across both Claude and Copilot agents.

## Scope

**Included:**
- Project initialization with interactive and non-interactive modes
- Policy creation and editing with proxy auto-restart
- Compose file editing with restart warnings
- Image digest pinning during init and bump-to-latest
- Command execution in running or stopped containers
- Full teardown (containers, volumes, config directories)
- Version reporting from git or .version file
- Docker Compose passthrough for unlisted commands
- Docker image distribution for zero-dependency usage
- BATS test suite covering all modules and shared libraries

**Excluded:**
- Go rewrite (m12)
- Fine-grained proxy rules (m14)
- Interactive monitoring/unblocking (m15)

## Applicable Learnings

- Policy files must live outside the workspace and be mounted read-only. The CLI creates policy files in `.agent-sandbox/` on the host; they're mounted read-only into the proxy container.
- Entrypoint scripts should be idempotent. The CLI's `exec` command starts the compose stack only if containers aren't already running.
- Relative paths in docker-compose files resolve from the compose file's directory, not the project root. The `init` command accounts for this when writing templates.
- VS Code devcontainers bypass Docker ENTRYPOINT. The CLI generates separate compose files for CLI and devcontainer modes to handle this difference.
- HTTP/2 must be disabled for Go programs behind mitmproxy. Templates include `GODEBUG=http2client=0` for the gh CLI.

## Architecture

```
cli/
├── bin/agentbox              # Entry point, modular dispatcher
├── lib/                      # Shared libraries (8 files)
│   ├── composefile.bash      # Compose file manipulation
│   ├── path.bash             # Path and file utilities
│   ├── select.bash           # User interaction helpers
│   ├── logging.bash          # Colored logging
│   ├── constants.bash        # Shared constants
│   ├── require.bash          # Dependency checking
│   ├── compat.bash           # Bash 3.2 compatibility shim
│   └── run-compose           # Docker Compose wrapper
├── libexec/                  # Command modules (6 modules, 12 scripts)
│   ├── init/                 # init, cli, devcontainer, policy
│   ├── edit/                 # edit, compose, policy
│   ├── bump/                 # bump, bump_service
│   ├── exec/                 # exec, _ (fallback)
│   ├── destroy/              # destroy
│   └── version/              # version
├── templates/                # Per-agent, per-mode templates
│   ├── policy.yaml
│   ├── claude/{cli,devcontainer}/
│   └── copilot/{cli,devcontainer}/
└── test/                     # BATS test suite (19 files)
```

The dispatcher scans `libexec/` for modules. First argument selects the module, second selects the command within it. Unmatched commands pass through to `docker compose`.

## Design Decisions

### Bash over compiled language

The CLI is pure Bash. This matches the host environment (macOS / Linux), keeps the dependency list short (`docker`, `yq`), and avoids a build step. The tradeoff is limited data structure support and test tooling. The Go rewrite (m12) addresses this for longer-term development.

### Modular dispatch

Each command lives in its own file under `libexec/<module>/`. Adding a new command means dropping a file in the right directory. The dispatcher discovers modules at runtime by scanning the directory tree, so no registration is needed.

### Image pinning at init time

During `agentbox init`, images are pulled and pinned to their digest (`@sha256:...`). This makes environments reproducible by default. The `bump` command updates digests to latest when the user chooses.

### Dual distribution (git clone + Docker image)

The CLI is distributed as both a git clone (add `cli/bin` to PATH) and a Docker image (`ghcr.io/mattolson/agent-sandbox-cli`). The Docker image eliminates local dependency requirements but trades off editor integration and startup speed.

### Policy auto-restart

`agentbox edit policy` detects whether the file changed and automatically restarts the proxy container. This eliminates the "edit policy, forget to restart, wonder why nothing changed" failure mode.

## Tasks

### m5.1-dispatcher-and-libraries (DONE)

Build the CLI entry point and shared library layer.

- [x] Dispatcher script with modular command routing
- [x] Environment setup (AGB_ROOT, AGB_LIBDIR, AGB_LIBEXECDIR, AGB_TEMPLATEDIR)
- [x] Docker Compose passthrough for unmatched commands
- [x] Shared libraries: logging, path utilities, constants, require, compat
- [x] Bash 3.2 compatibility shim (mapfile polyfill)
- [x] ShellCheck configuration
- [x] BATS test infrastructure and conventions

### m5.2-init-command (DONE)

Scaffold sandbox configuration for a project.

- [x] Interactive mode: prompt for agent, mode, IDE, name, path
- [x] Non-interactive mode: `--agent`, `--mode`, `--ide`, `--name`, `--path` flags
- [x] CLI mode: generate `.agent-sandbox/docker-compose.yml`
- [x] Devcontainer mode: generate `.devcontainer/docker-compose.yml` and `devcontainer.json`
- [x] Policy file creation from template with service injection via yq
- [x] Image pull and digest pinning during init
- [x] Compose file customization library (volumes, env vars, IDE-specific capabilities)
- [x] Per-agent templates for Claude and Copilot, both CLI and devcontainer modes
- [x] JetBrains-specific capabilities (DAC_OVERRIDE, CHOWN, FOWNER)

### m5.3-edit-command (DONE)

Edit policy and compose files with operational awareness.

- [x] `agentbox edit policy`: open policy file in user's editor
- [x] `agentbox edit compose`: open compose file in user's editor
- [x] Auto-detect compose file location (`.agent-sandbox/` or `.devcontainer/`)
- [x] Track file modification time before/after edit
- [x] Auto-restart proxy if policy changed and containers are running
- [x] Warn to restart if compose file changed while containers are running
- [x] `--mode` and `--agent` flags to filter when multiple policy files exist
- [x] Editor resolution: `$VISUAL` > `$EDITOR` > `open` (macOS) > `vi`

### m5.4-bump-command (DONE)

Update pinned image digests to latest.

- [x] Find compose file automatically
- [x] Iterate proxy and agent services
- [x] Pull latest image and extract new digest
- [x] Skip local images (`:local` tag or unqualified names)
- [x] Compare old vs new digest, update only if changed
- [x] Logging of what was pulled and whether digest changed

### m5.5-exec-command (DONE)

Run commands inside the agent container.

- [x] Check if agent container is running
- [x] Start full compose stack if not running
- [x] Execute arbitrary command in container
- [x] Default to interactive zsh shell when no command given
- [x] Fallback handler for unmatched subcommands

### m5.6-destroy-command (DONE)

Clean up sandbox configuration and resources.

- [x] Confirmation prompt before destructive operation
- [x] `--force` flag to skip confirmation
- [x] Stop and remove containers with volumes (`docker compose down --volumes`)
- [x] Remove `.agent-sandbox/` directory
- [x] Remove `.devcontainer/` directory

### m5.7-version-command (DONE)

Report CLI version.

- [x] Read from `.version` file (published releases)
- [x] Fall back to git-based version (date + short SHA)
- [x] Handle missing git gracefully

### m5.8-distribution (DONE)

Package the CLI for users.

- [x] Git clone installation path (add `cli/bin` to PATH)
- [x] Docker image (`ghcr.io/mattolson/agent-sandbox-cli`)
- [x] Docker socket mount for container management from inside image
- [x] `--network none` for CLI image (no outbound needed)

## Execution Order

The tasks were sequenced to build foundation first, then commands in dependency order:

1. **m5.1** - Dispatcher and libraries (everything depends on this)
2. **m5.2** - Init (creates the config files other commands operate on)
3. **m5.3** - Edit (modifies files created by init)
4. **m5.4** - Bump (updates images referenced in compose files)
5. **m5.5** - Exec (runs containers defined by compose files)
6. **m5.6** - Destroy (tears down what init created)
7. **m5.7** - Version (standalone, no ordering constraint)
8. **m5.8** - Distribution (requires all commands to exist)

m5.5 through m5.7 had no hard dependencies on each other and could have been parallelized.

## Risks

No significant risks materialized. The main concerns going in were:

- **Bash compatibility across macOS/Linux**: Mitigated by the Bash 3.2 compat shim and strict ShellCheck enforcement.
- **yq as a dependency**: Acceptable tradeoff for YAML manipulation. The Docker image distribution eliminates this for users who don't want to install yq locally. Resolved long-term by the Go rewrite (m12).
- **Template maintenance burden**: Two agents x two modes = four compose templates. Manageable at current scale; would need a generation approach if agent count grows significantly.

## Definition of Done

- [x] All six commands work: init, edit, bump, exec, destroy, version
- [x] CLI and devcontainer modes supported for both Claude and Copilot
- [x] Interactive and non-interactive init flows
- [x] Policy editing auto-restarts proxy
- [x] Image digests pinned at init, updatable via bump
- [x] BATS test suite with 19 test files covering all modules and libraries
- [x] Docker image published for zero-dependency usage
- [x] Documentation in README
