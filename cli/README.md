# Agent Sandbox CLI

Install `agentbox` from GitHub Releases. See the [main README](../README.md#2-install-agent-sandbox-cli) for the
download steps.

This document is the command reference for the current `agentbox` surface and the maintenance guide for the legacy Bash
implementation that still lives under `cli/` during the transition. That legacy path still depends on `docker`, `docker
compose`, and [`yq`](https://github.com/mikefarah/yq).

## Docker Image Fallback

The old Docker CLI image is still available during the transition:

```bash
docker pull ghcr.io/mattolson/agent-sandbox-cli
alias agentbox='docker run --rm -it -v "/var/run/docker.sock:/var/run/docker.sock" -v"$PWD:$PWD" -w"$PWD" -e TERM -e HOME --network none ghcr.io/mattolson/agent-sandbox-cli'
```

Tradeoffs:
- Commands such as `agentbox edit policy` use `vi` inside the container rather than your host editor
- Host environment variables are not automatically visible to Docker Compose unless you forward them explicitly
- The image remains on the old CLI implementation until follow-up work removes that path

## Modules and Commands

### `agentbox init`

Initializes agent-sandbox for a project. Prompts for any options not provided via flags, then sets up the necessary
configuration files and network policy. In CLI mode, agentbox writes managed compose layers under
`.agent-sandbox/compose/`, creates a shared user-owned override at `.agent-sandbox/compose/user.override.yml`, and
creates `.agent-sandbox/policy/user.policy.yaml` plus the active agent's
`.agent-sandbox/policy/user.agent.<agent>.policy.yaml` alongside the managed agent layer. Optional mounts (Claude
config, shell customizations, dotfiles, `.git`, `.idea`, `.vscode`) are scaffolded into user-owned override files
instead of managed files. After generation, `init` reminds you to use `agentbox policy config` and
`agentbox compose config` to inspect the effective rendered configuration. For devcontainer mode, agentbox writes `.devcontainer/devcontainer.json`
plus optional `.devcontainer/devcontainer.user.json`, while the managed compose and policy runtime files live under
`.agent-sandbox/`. `devcontainer.user.json` is an agentbox overlay input, not a second devcontainer config file that
VS Code or JetBrains reads directly: agentbox merges it into the generated `.devcontainer/devcontainer.json` during
init and refresh paths.

Options:
- `--agent` - Agent type: `claude`, `codex`, `copilot` (skips prompt)
- `--mode` - Setup mode: `cli`, `devcontainer` (skips prompt)
- `--ide` - IDE for devcontainer mode: `vscode`, `jetbrains`, `none` (skips prompt)
- `--name` - Base project name for Docker Compose. CLI uses it as-is; devcontainer appends `-devcontainer` to avoid collisions between modes.
- `--path` - Project directory (default: current directory)
- `--batch` - Disable prompts. Requires `--agent` and `--mode`, plus `--ide` for `devcontainer`.

Fully non-interactive example:
```bash
agentbox init --batch --agent claude --mode cli --name myproject --path /some/dir
```

If `init` detects a legacy single-file layout, it fails fast with rename-and-rerun guidance and points to the
[upgrade guide](../docs/upgrades/m8-layered-layout.md).

### `agentbox switch`

Updates the active agent for an initialized project. For layered CLI projects, switching lazily creates the target
agent's managed compose layer, agent-specific user policy scaffold, and agent-specific override scaffold the first time
that agent is selected. For devcontainer projects, switching also refreshes the centralized `.agent-sandbox` runtime
files and regenerates `.devcontainer/devcontainer.json` for the selected agent while preserving
`.devcontainer/devcontainer.user.json` and reusing the stored IDE selection. If `--agent` is omitted, prompts once for
the new active agent. This same-agent refresh path is also the explicit way to re-merge edits from
`.devcontainer/devcontainer.user.json` into the generated `.devcontainer/devcontainer.json`. If the current compose
stack is running, `switch` reconciles it immediately by running `docker compose down` followed by `docker compose up -d`
through the layered runtime wrapper, so the selected agent and mounted config stay in sync.

If the project is still on the legacy single-file layout, `switch` fails fast and points to the
[upgrade guide](../docs/upgrades/m8-layered-layout.md).

Options:
- `--agent` - Agent type: `claude`, `codex`, `copilot` (skips prompt)

#### `agentbox init cli`

Sets up CLI mode layered Docker Compose configuration for an agent.

Options:
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)
- `--name` - Base project name for Docker Compose (default and rendered compose project name: `{dir}-sandbox`)

#### `agentbox init devcontainer`

Sets up a devcontainer configuration for an agent. Writes the IDE-facing `.devcontainer/devcontainer.json`, optional
`.devcontainer/devcontainer.user.json`, and centralized sandbox runtime files under `.agent-sandbox/`. The optional
user file is merged by agentbox into the generated `devcontainer.json`; it is not read directly by devcontainer
tooling.

Options:
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)
- `--ide` - The IDE name (e.g., `vscode`, `jetbrains`, `none`)
- `--name` - Base project name for Docker Compose (default base: `{dir}-sandbox`, rendered compose project name: `{dir}-sandbox-devcontainer`)

#### `agentbox init policy`

Creates a network policy file for the proxy.

Arguments:
- First argument: Path to the policy file
- Remaining arguments: Service names to include (e.g., `claude`, `copilot`, `vscode`, `jetbrains`)

### `agentbox destroy`

Removes all agent-sandbox configuration and containers from a project. Stops running containers, removes volumes, and
deletes configuration directories.

### Legacy upgrades

Current runtime and edit commands no longer operate on pre-layered single-file layouts such as:

- `.agent-sandbox/docker-compose.yml`
- `.devcontainer/docker-compose.yml`
- `.agent-sandbox/policy-cli-<agent>.yaml`
- `.agent-sandbox/policy-devcontainer-<agent>.yaml`

When those files are detected, commands fail fast with a short rename-and-rerun summary and point to the
[upgrade guide](../docs/upgrades/m8-layered-layout.md) for the full upgrade procedure.

### `agentbox version`

Displays the current version of agent-sandbox.

### `agentbox edit compose`

Opens the user-editable Docker Compose surface in your editor. For layered CLI projects this is
`.agent-sandbox/compose/user.override.yml`. Devcontainer projects using the centralized layout reuse that same file.
Legacy single-file compose layouts are no longer edited in place; current commands point to the upgrade guide instead.
If you save changes and containers are running, it will restart containers by default to apply the changes.

Options:
- `--no-restart` — Do not automatically restart containers after changes. When set (or when `AGENTBOX_NO_RESTART=true`), a warning is shown instead with instructions to run `agentbox up -d` manually.

### `agentbox edit policy`

Opens the network policy file in your editor. If you save changes, the proxy service will automatically restart to apply
the new policy. For layered CLI projects, the default target is `.agent-sandbox/policy/user.policy.yaml`, and `--agent
<name>` targets `.agent-sandbox/policy/user.agent.<name>.policy.yaml`. Current devcontainer projects do not have a
separate user-editable devcontainer policy file, so `--mode devcontainer` reuses those same layered policy surfaces.
Legacy flat `policy-<mode>-<agent>.yaml` files are no longer opened in place; current commands point to the upgrade
guide instead.

### `agentbox policy config`

Renders the effective policy that the proxy enforces. In layered CLI projects this merges the active agent baseline with
`.agent-sandbox/policy/user.policy.yaml` and `.agent-sandbox/policy/user.agent.<active-agent>.policy.yaml` by invoking
the same proxy-side render helper used at runtime. For devcontainer projects, the same render path also layers the
managed `.agent-sandbox/policy/policy.devcontainer.yaml`.

`agentbox policy render` remains available as an alias.

### `agentbox bump`

Updates Docker images to their latest digests. For layered CLI projects, this updates the managed base layer plus any
initialized agent layers without touching user-owned override files. Devcontainer projects reuse those same managed
`.agent-sandbox/compose/*.yml` layers and user-owned override files. Skips local images.

### `agentbox up`

Runs `docker compose up` with the correct layered compose stack automatically detected.

### `agentbox down`

Runs `docker compose down` with the correct layered compose stack automatically detected.

### `agentbox logs`

Runs `docker compose logs` with the correct layered compose stack automatically detected.

### `agentbox compose`

Runs arbitrary `docker compose` commands with the correct layered compose stack automatically detected
(for example `agentbox compose ps`).

### `agentbox exec`

Runs a command inside the agent container. If no command is specified, opens a shell. Example: `agentbox exec` opens a
shell, `agentbox exec npm install` runs npm inside the container.

## Directory Structure

Each module is contained in its own directory under `cli/libexec/`.
Modules can be decomposed into multiple commands, the default command being the module's name
(e.g.`cli/libexec/init/init`)
The entrypoint extends the `PATH` with the current module's libexec directory, so that it can call other commands in the
same module by their name.

```
cli/
├── bin/
│   └── agentbox           # Main CLI entry point
├── lib/                   # Shared library functions
├── libexec/               # Module implementations
│   ├── destroy/           #    Each module can contain multiple commands
│   ├── init/
│   └── version/
├── support/               # BATS and it's extensions
├── templates/             # Configuration templates
└── test/             	   # BATS tests
```

## Environment Variables

### Internal (set by the CLI)

- `AGB_ROOT` - Root directory of agent-sandbox CLI
- `AGB_LIBDIR` - Library directory (default: `$AGB_ROOT/lib`)
- `AGB_LIBEXECDIR` - Directory for module implementations (default: `$AGB_ROOT/libexec`)
- `AGB_TEMPLATEDIR` - Directory for templates (default: `$AGB_ROOT/templates`)

### Configuration (set before running `agentbox init`)

These override defaults during compose generation. Optional mounts default to `false`. In layered CLI mode they are
written into user-owned override scaffolds instead of managed files. In devcontainer mode they are written into
`.agent-sandbox/compose/user.override.yml` and `.agent-sandbox/compose/user.agent.<agent>.override.yml` when those
files are first scaffolded.

- `AGENTBOX_PROXY_IMAGE` - Docker image for proxy service (default: latest published proxy image)
- `AGENTBOX_AGENT_IMAGE` - Docker image for the active agent service during CLI init (default: latest published image for that agent)
- `AGENTBOX_MOUNT_CLAUDE_CONFIG` - `true` to mount host `~/.claude` config (Claude agent only)
- `AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS` - `true` to mount `~/.config/agent-sandbox/shell.d`
- `AGENTBOX_ENABLE_DOTFILES` - `true` to mount `~/.config/agent-sandbox/dotfiles`
- `AGENTBOX_MOUNT_GIT_READONLY` - `true` to mount `.git/` directory as read-only
- `AGENTBOX_MOUNT_IDEA_READONLY` - `true` to mount `.idea/` directory as read-only (JetBrains)
- `AGENTBOX_MOUNT_VSCODE_READONLY` - `true` to mount `.vscode/` directory as read-only (VS Code)
