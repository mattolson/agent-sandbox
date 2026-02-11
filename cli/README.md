# Agent Sandbox CLI

Command-line tool for managing agent-sandbox configurations and Docker Compose setups.

## Modules

### `agentbox init`

Initializes agent-sandbox for a project.

### `agentbox clean`

Removes the agent-sandbox files for a project.

### `agentbox version`

Displays version information for the agent-sandbox project.

### `agentbox bump`

Updates Docker images in the compose file to their latest digests. Reads the current images from the compose file, pulls the latest versions, and updates the compose file with the new digests. Local images (with `:local` tag or without registry prefix) are skipped.

## Directory Structure

Each module is contained in its own directory under `cli/libexec/`.
Modules can be decomposed into multiple commands, the default command being the module's name (e.g. `cli/libexec/init/init`)
The entrypoint extends the `PATH` with the current module's libexec directory, so that it can call other commands 
in the same module by their name.

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
