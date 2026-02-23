# Agent Sandbox CLI

Command-line tool for managing agent-sandbox configurations and Docker Compose setups.

Requires `docker` (and `docker compose`) and [`yq`](https://github.com/mikefarah/yq).

## Modules and Commands

### `agentbox init`

Initializes agent-sandbox for a project. Prompts for any options not provided via flags, then sets up the necessary
configuration files and network policy. Optional volume mounts (Claude config, shell customizations, dotfiles, .git,
.idea, .vscode) are included as commented-out entries in the generated compose file.

Options:
- `--agent` - Agent type: `claude`, `copilot` (skips prompt)
- `--mode` - Setup mode: `cli`, `devcontainer` (skips prompt)
- `--ide` - IDE for devcontainer mode: `vscode`, `jetbrains`, `none` (skips prompt)
- `--name` - Project name for Docker Compose (default: derived from directory name)
- `--path` - Project directory (default: current directory)

Fully non-interactive example:
```bash
agentbox init --agent claude --mode cli --name myproject --path /some/dir
```

#### `agentbox init cli`

Sets up CLI mode docker-compose configuration for an agent. Copies the docker-compose.yml template and customizes it
based on the selected agent.

Options:
- `--policy-file` - Path to the policy file (relative to project directory)
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

Opens the Docker Compose file in your editor. If you save changes and containers are running, warns you to restart.

### `agentbox edit policy`

Opens the network policy file in your editor. If you save changes, the proxy service will automatically restart to apply
the new policy. Use `--mode` and `--agent` to select specific policy files.

### `agentbox bump`

Updates Docker images to their latest versions by pulling the newest digests and updating the compose file. Skips local
images.

### Docker compose passthrough

Any unrecognized command is passed through to `docker compose` with the correct compose file automatically detected
(e.g., `agentbox up -d` or `agentbox logs`).

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

These override defaults during compose file generation. Optional volumes default to `false` (commented out).

- `AGENTBOX_PROXY_IMAGE` - Docker image for proxy service (default: latest published proxy image)
- `AGENTBOX_AGENT_IMAGE` - Docker image for agent service (default: latest published agent image)
- `AGENTBOX_MOUNT_CLAUDE_CONFIG` - `true` to mount host `~/.claude` config (Claude agent only)
- `AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS` - `true` to mount `~/.config/agent-sandbox/shell.d`
- `AGENTBOX_ENABLE_DOTFILES` - `true` to mount `~/.config/agent-sandbox/dotfiles`
- `AGENTBOX_MOUNT_GIT_READONLY` - `true` to mount `.git/` directory as read-only
- `AGENTBOX_MOUNT_IDEA_READONLY` - `true` to mount `.idea/` directory as read-only (JetBrains)
- `AGENTBOX_MOUNT_VSCODE_READONLY` - `true` to mount `.vscode/` directory as read-only (VS Code)
