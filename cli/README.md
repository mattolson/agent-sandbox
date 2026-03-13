# Agent Sandbox CLI

Command-line tool for managing agent-sandbox configurations and Docker Compose setups.

Requires `docker` (and `docker compose`) and [`yq`](https://github.com/mikefarah/yq).

## Modules and Commands

### `agentbox init`

Initializes agent-sandbox for a project. Prompts for any options not provided via flags, then sets up the necessary
configuration files and network policy. In CLI mode, agentbox writes managed compose layers under
`.agent-sandbox/compose/`, creates a shared user-owned override at `.agent-sandbox/compose/user.override.yml`, and
creates `.agent-sandbox/user.policy.yaml` plus the active agent's `.agent-sandbox/user.agent.<agent>.policy.yaml`
alongside the managed agent layer. Optional mounts (Claude config, shell customizations, dotfiles, `.git`, `.idea`,
`.vscode`) are scaffolded into user-owned override files instead of managed files. After generation, `init` offers to
open the shared user-owned policy file and shared compose override in your editor. These review prompts default to
`no`.

Options:
- `--agent` - Agent type: `claude`, `copilot`, `codex` (skips prompt)
- `--mode` - Setup mode: `cli`, `devcontainer` (skips prompt)
- `--ide` - IDE for devcontainer mode: `vscode`, `jetbrains`, `none` (skips prompt)
- `--name` - Project name for Docker Compose (default: derived from directory name)
- `--path` - Project directory (default: current directory)
- `--batch` - Disable prompts, including generated-file review prompts. Requires `--agent` and `--mode`, plus `--ide` for `devcontainer`.

Fully non-interactive example:
```bash
agentbox init --batch --agent claude --mode cli --name myproject --path /some/dir
```

### `agentbox switch`

Updates the active agent for an initialized project. For layered CLI projects, switching lazily creates the target
agent's managed compose layer, agent-specific user policy scaffold, and agent-specific override scaffold the first time
that agent is selected. Interim `policy-cli-<agent>.yaml` files from `m8.2` are carried forward into the new
user-owned policy file and renamed to a conspicuous deprecated filename. If `--agent` is omitted, prompts once for the
new active agent.

Options:
- `--agent` - Agent type: `claude`, `copilot`, `codex` (skips prompt)

#### `agentbox init cli`

Sets up CLI mode layered Docker Compose configuration for an agent.

Options:
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)
- `--name` - Project name for Docker Compose (default: `{dir}-sandbox`)

#### `agentbox init devcontainer`

Sets up a devcontainer configuration for an agent. Copies devcontainer template files and customizes the
docker-compose.yml.

Options:
- `--policy-file` - Path to the policy file (relative to project directory)
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)
- `--ide` - The IDE name (e.g., `vscode`, `jetbrains`, `none`) (optional)
- `--name` - Project name for Docker Compose (default: `{dir}-sandbox-devcontainer`)

#### `agentbox init policy`

Creates a network policy file for the proxy.

Arguments:
- First argument: Path to the policy file
- Remaining arguments: Service names to include (e.g., `claude`, `copilot`, `vscode`, `jetbrains`)

### `agentbox destroy`

Removes all agent-sandbox configuration and containers from a project. Stops running containers, removes volumes, and
deletes configuration directories.

### `agentbox version`

Displays the current version of agent-sandbox.

### `agentbox edit compose`

Opens the user-editable Docker Compose surface in your editor. For layered CLI projects this is
`.agent-sandbox/compose/user.override.yml`; otherwise it falls back to the single compose file. If you save changes and
containers are running, it will restart containers by default to apply the changes.

Options:
- `--no-restart` — Do not automatically restart containers after changes. When set (or when `AGENTBOX_NO_RESTART=true`), a warning is shown instead with instructions to run `agentbox up -d` manually.

### `agentbox edit policy`

Opens the network policy file in your editor. If you save changes, the proxy service will automatically restart to apply
the new policy. For layered CLI projects, the default target is `.agent-sandbox/user.policy.yaml`, and `--agent
<name>` targets `.agent-sandbox/user.agent.<name>.policy.yaml`. For devcontainer and legacy layouts, `--mode` and
`--agent` continue to select flat policy files.

### `agentbox policy render`

Renders the effective policy that the proxy enforces. In layered CLI projects this merges the active agent baseline with
`.agent-sandbox/user.policy.yaml` and `.agent-sandbox/user.agent.<active-agent>.policy.yaml` by invoking the same
proxy-side render helper used at runtime.

### `agentbox bump`

Updates Docker images to their latest digests. For layered CLI projects, this updates the managed base layer plus any
initialized agent layers without touching user-owned override files. Skips local images.

### `agentbox up`

Runs `docker compose up` with the correct compose stack automatically detected.

### `agentbox down`

Runs `docker compose down` with the correct compose stack automatically detected.

### `agentbox logs`

Runs `docker compose logs` with the correct compose stack automatically detected.

### `agentbox compose`

Runs arbitrary `docker compose` commands with the correct compose stack automatically detected
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
written into user-owned override scaffolds instead of managed files.

- `AGENTBOX_PROXY_IMAGE` - Docker image for proxy service (default: latest published proxy image)
- `AGENTBOX_AGENT_IMAGE` - Docker image for the active agent service during CLI init (default: latest published image for that agent)
- `AGENTBOX_MOUNT_CLAUDE_CONFIG` - `true` to mount host `~/.claude` config (Claude agent only)
- `AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS` - `true` to mount `~/.config/agent-sandbox/shell.d`
- `AGENTBOX_ENABLE_DOTFILES` - `true` to mount `~/.config/agent-sandbox/dotfiles`
- `AGENTBOX_MOUNT_GIT_READONLY` - `true` to mount `.git/` directory as read-only
- `AGENTBOX_MOUNT_IDEA_READONLY` - `true` to mount `.idea/` directory as read-only (JetBrains)
- `AGENTBOX_MOUNT_VSCODE_READONLY` - `true` to mount `.vscode/` directory as read-only (VS Code)
