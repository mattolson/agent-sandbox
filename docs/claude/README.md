# Claude Code Sandbox Template

Run Claude Code in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "claude") and starting the sandbox, authenticate Claude on first run.

### Authenticate Claude (first run only)

Do **not** use the page that automatically opens in your browser. It will try to connect to localhost and fail. Instead:

1. Copy the URL and open it in your browser (this URL uses a different flow than the one that opens automatically)
2. Authorize the application
3. Paste the authorization code

[<img src="../../docs/images/claude-auth-vscode-ide.png" alt="Claude authentication from VS Code IDE" width="200"/>](../images/claude-auth-vscode-ide.png)
[<img src="../../docs/images/claude-auth-vscode-terminal.png" alt="Claude authentication from VS Code terminal" width="200"/>](../images/claude-auth-vscode-terminal.png)

Credentials persist in a Docker volume. You only need to do this once per project.

### Use Claude Code

Inside the container:

```bash
claude
# or to auto-approve all actions:
claude --dangerously-skip-permissions
```

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```

## Terminal vs IDE Extension

You can run Claude Code two ways within the container:

| Mode | How to start                                                   | IDE support |
|------|----------------------------------------------------------------|-------------|
| **Terminal** | Run `claude` in the integrated terminal                        | VS Code, JetBrains |
| **IDE extension** | `devcontainer.json` should install the extension automatically | VS Code, JetBrains |


### JetBrains IDE
The JetBrains IDE plugin has very limited features.
Most of the work happens in the terminal, but it will allow you to review changes in the GUI diff viewer.

To use this feature, make sure that "Open devcontainer projects natively" is **disabled** in "Advanced Settings"

To start, either click the Claude Code icon in the status bar or run `claude` from the (remote) terminal.
When Claude is running use `/ide` command to connect the IDE to Claude.

[<img src="../../docs/images/idea-claude-connect.png" alt="Claude Code JetBrains plugin" width="200"/>](../images/idea-claude-connect.png)

If you encounter issues, make sure that the extension is installed on "host" (this is the container).

[<img src="../../docs/images/idea-claude-plugin-on-host.png" alt="Claude Code JetBrains plugin installed on host" width="200"/>](../images/idea-claude-plugin-on-host.png)

If you can see ` > 1. IntelliJ IDEA `    ` after issuing `/ide` command, but the integration is not working, check the `/status`.
You should see `Connected to IntelliJ IDEA extension`, otherwise remove the Devcontainers containers and volumes and try again.

[<img src="../../docs/images/idea-claude-plugin-connected.png" alt="Claude Code JetBrains plugin connected" width="200"/>](../images/idea-claude-plugin-connected.png)

### VS Code
In VS Code, both modes work with the sandbox container. The IDE extension runs a separately bundled claude binary, but the proxy and firewall apply equally because both binaries run inside the container and respect the `HTTP_PROXY` environment variable.

**Shared configuration.** Both modes use the same Claude credentials and settings stored in the Docker volume (`~/.claude`). You can switch between terminal and extension freely. Authenticate once in either mode and both will work.

**Feature differences.** The IDE extension provides tighter editor integration (inline suggestions, chat panel). The terminal provides the full CLI feature set. Use whichever fits your workflow, or both.

**First-time setup with extension.** If you start fresh with the extension (no prior authentication), the extension will prompt you to authenticate through its UI. This works the same as the terminal OAuth flow.

**Connecting terminal to IDE.** Running `/ide` in the terminal Claude session shows the connection status to VS Code. When connected, Claude can interact with the editor directly.

## Required Network Policy

The Claude service requires these services:

```yaml
services:
  - claude  # Anthropic Claude API
```

See the [main README](../../README.md#network-policy) for policy customization and verification.
