# Agent Sandbox CLI

Command-line tool for managing agent-sandbox configurations and Docker Compose setups.

Requires `docker` (and `docker compose`) and [`yq`](https://github.com/mikefarah/yq).

## Modules and Commands

### `agentbox init`

Initializes agent-sandbox for a project. Prompts you to select the agent type and mode, then sets up the necessary
configuration files and network policy.

#### `agentbox init cli`

Sets up CLI mode docker-compose configuration for an agent. Copies the docker-compose.yml template and customizes it
based on the selected agent.

Options:
- `--policy-file` - Path to the policy file (relative to project directory)
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)

#### `agentbox init devcontainer`

Sets up a devcontainer configuration for an agent. Copies devcontainer template files and customizes the
docker-compose.yml.

Options:
- `--policy-file` - Path to the policy file (relative to project directory)
- `--project-path` - Path to the project directory
- `--agent` - The agent name (e.g., `claude`)
- `--ide` - The IDE name (e.g., `vscode`, `jetbrains`, `none`) (optional)

#### `agentbox init policy`

Creates a network policy file for the proxy.

Arguments:
- First argument: Path to the policy file
- Remaining arguments: Service names to include (e.g., `claude`, `copilot`, `vscode`, `jetbrains`)

### `agentbox clean`

Removes all agent-sandbox configuration and containers from a project. Stops running containers, removes volumes, and
deletes configuration directories.

### `agentbox version`

Displays the current version of agent-sandbox.

### `agentbox compose`

Runs docker compose commands with the correct compose file automatically detected. Pass any docker compose arguments
(e.g., `agentbox compose up -d` or `agentbox compose logs`).

#### `agentbox compose edit`

Opens the Docker Compose file in your editor. If you save changes, the stack will automatically restart to apply the new
configuration.

#### `agentbox compose bump`

Updates Docker images to their latest versions by pulling the newest digests and updating the compose file. Skips local
images.

### `agentbox policy`

Opens the network policy file in your editor. If you save changes, the proxy service will automatically restart to apply
the new policy. Use `--mode` and `--agent` to select specific policy files.

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
│   ├── clean/             #    Each module can contain multiple commands
│   ├── init/
│   └── version/
├── support/               # BATS and it's extensions
├── templates/             # Configuration templates
└── test/             	   # BATS tests
```

## Environment Variables

- `AGB_ROOT` - Root directory of agent-sandbox CLI
- `AGB_LIBDIR` - Library directory (default: `$AGB_ROOT/lib`)
- `AGB_LIBEXECDIR` - Directory for module implementations (default: `$AGB_ROOT/libexec`)
- `AGB_TEMPLATEDIR` - Directory for templates (default: `$AGB_ROOT/templates`)
