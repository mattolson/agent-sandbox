# Agent Sandbox CLI

Command-line tool for managing agent-sandbox configurations and Docker Compose setups.

## Modules and Commands

### `agentbox init`

Initializes agent-sandbox for a project. Prompts you to select the agent type and mode, then sets up the necessary
configuration files and network policy.

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
- `AGB_TEMPLATEDIR` - Directory for templates (default: `$AGB_ROOT/templates`)
