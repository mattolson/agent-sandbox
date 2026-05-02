# Agentbox CLI Reference

Reference for the Go `agentbox` CLI.

## Manual Install

Download the platform archive directly from [GitHub Releases](https://github.com/mattolson/agent-sandbox/releases) if
you do not want to use the installer script.

```bash
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

ASSET="agentbox_${OS}_${ARCH}.tar.gz"

cd /tmp
curl -fsSLO \
  "https://github.com/mattolson/agent-sandbox/releases/latest/download/${ASSET}"
tar -xzf "${ASSET}"
mkdir -p "${HOME}/.local/bin"
install -m 755 "/tmp/agentbox_${OS}_${ARCH}/agentbox" "${HOME}/.local/bin/agentbox"
"${HOME}/.local/bin/agentbox" version
```

To verify the archive before installing it, download `agentbox_checksums.txt` from the same release and compare the
checksum for `${ASSET}` against `shasum -a 256 "${ASSET}"` on macOS or `sha256sum "${ASSET}"` on Linux.

For a pinned install instead of "latest", use the versioned assets attached to a specific release tag, such as
`agentbox_<version>_<os>_<arch>.tar.gz` together with `agentbox_<version>_checksums.txt`.

If `~/.local/bin` is not already on your `PATH`, add it in your shell profile before running `agentbox` directly.

## Commands

### `agentbox init`

Initializes a project sandbox. Prompts for any options not provided via flags, then writes the managed compose and
policy layers under `.agent-sandbox/` plus `.devcontainer/devcontainer.json` for devcontainer mode.

Options:
- `--agent` - Agent type: `claude`, `codex`, `copilot`, `gemini`, `factory`, `pi`, `opencode`
- `--mode` - Setup mode: `cli`, `devcontainer`
- `--ide` - IDE for devcontainer mode: `vscode`, `jetbrains`, `none`
- `--name` - Base project name for Docker Compose
- `--path` - Project directory (default: current directory)
- `--batch` - Disable prompts. Requires `--agent` and `--mode`, plus `--ide` for `devcontainer`

Example:

```bash
agentbox init --batch --agent claude --mode cli --name myproject --path /some/dir
```

If `init` detects a legacy single-file layout, it fails fast with rename-and-rerun guidance and points to the
[upgrade guide](upgrades/m8-layered-layout.md).

### `agentbox switch`

Updates the active agent for an initialized project. For layered CLI projects, switching lazily creates the target
agent's managed compose layer, agent-specific user policy scaffold, and agent-specific override scaffold the first time
that agent is selected. For devcontainer projects, switching also refreshes the centralized `.agent-sandbox` runtime
files and regenerates `.devcontainer/devcontainer.json` for the selected agent while preserving
`.devcontainer/devcontainer.user.json` and reusing the stored IDE selection.

Options:
- `--agent` - Agent type

### `agentbox edit compose`

Opens the user-editable Docker Compose surface in your editor. For layered CLI and centralized devcontainer projects
this is `.agent-sandbox/compose/user.override.yml`. If you save changes and containers are running, it restarts the
runtime by default.

Options:
- `--no-restart` - Do not automatically restart containers after changes

### `agentbox edit policy`

Opens the network policy file in your editor. For layered CLI projects, the default target is
`.agent-sandbox/policy/user.policy.yaml`, and `--agent <name>` targets
`.agent-sandbox/policy/user.agent.<name>.policy.yaml`. If you save changes affecting the active runtime and the proxy
is running, the proxy policy hot-reloads automatically.

### `agentbox policy config`

Renders the effective policy that the proxy enforces.

`agentbox policy render` remains available as an alias.

### `agentbox proxy reload`

Sends `SIGHUP` to the running proxy container so it re-renders the effective policy and atomically swaps the matcher.
Use this after editing any `.agent-sandbox/policy/*.yaml` file directly; `agentbox edit policy` already runs it for
active-policy changes. Existing connections are not interrupted; new requests see the new policy on the next match. A
bad policy keeps the previous matcher installed and emits a `rejected` event to the proxy log.

```bash
agentbox proxy reload
agentbox proxy logs   # look for {"type": "reload", "action": "applied" | "rejected"}
```

### `agentbox proxy logs`

Runs `docker compose logs proxy` with the correct layered compose stack automatically detected. This is the preferred
form when you only want proxy-side output.

### `agentbox bump`

Updates Docker images to their latest digests. For layered CLI projects, this updates the managed base layer plus any
initialized agent layers without touching user-owned override files.

### `agentbox up`

Runs `docker compose up` with the correct layered compose stack automatically detected.

### `agentbox down`

Runs `docker compose down` with the correct layered compose stack automatically detected.

### `agentbox logs`

Runs `docker compose logs` with the correct layered compose stack automatically detected.

### `agentbox compose`

Runs arbitrary `docker compose` commands with the correct layered compose stack automatically detected.

Example:

```bash
agentbox compose ps
```

### `agentbox exec`

Runs a command inside the agent container. If no command is specified, opens a shell.

Examples:

```bash
agentbox exec
agentbox exec npm install
```

### `agentbox destroy`

Removes all agent-sandbox configuration and containers from a project. Stops running containers, removes volumes, and
deletes configuration directories.

### `agentbox version`

Displays the current version metadata for `agentbox`.

### `agentbox completion`

Generates shell completion scripts for supported shells.

## Environment Variables

These override defaults during compose generation. Optional mounts default to `false`. In layered CLI mode they are
written into user-owned override scaffolds instead of managed files. In devcontainer mode they are written into
`.agent-sandbox/compose/user.override.yml` and `.agent-sandbox/compose/user.agent.<agent>.override.yml` when those
files are first scaffolded.

- `AGENTBOX_PROXY_IMAGE` - Docker image for proxy service
- `AGENTBOX_AGENT_IMAGE` - Docker image for the active agent service during init
- `AGENTBOX_MOUNT_CLAUDE_CONFIG` - `true` to mount host `~/.claude` config (Claude only)
- `AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS` - `true` to mount `~/.config/agent-sandbox/shell.d`
- `AGENTBOX_ENABLE_DOTFILES` - `true` to mount `~/.config/agent-sandbox/dotfiles`
- `AGENTBOX_MOUNT_GIT_READONLY` - `true` to mount `.git/` as read-only
- `AGENTBOX_MOUNT_IDEA_READONLY` - `true` to mount `.idea/` as read-only
- `AGENTBOX_MOUNT_VSCODE_READONLY` - `true` to mount `.vscode/` as read-only
- `AGENTBOX_NO_RESTART` - `true` to suppress automatic restart after `edit compose`
