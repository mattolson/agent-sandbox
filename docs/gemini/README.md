# Gemini CLI Sandbox Template

Run Gemini CLI in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "gemini") and starting the sandbox, authenticate Gemini on first run.

### Authenticate Gemini (first run only)

Two authentication methods are supported:

**API key** (simplest): Set the `GEMINI_API_KEY` environment variable before starting the container, or export it inside the container shell.

**Google OAuth**: Run `gemini` inside the container. On first run it will display a URL for browser-based authentication. Complete the flow in your browser.

Credentials persist in a Docker volume. You only need to do this once per project.

### Use Gemini CLI

Inside the container:

```bash
gemini
# or auto-approve mode:
gemini --approval-mode=yolo
```

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```

## Terminal vs IDE Extension

You can run Gemini CLI two ways within the container:

| Mode | How to start                                                   | IDE support |
|------|----------------------------------------------------------------|-------------|
| **Terminal** | Run `gemini` in the integrated terminal                        | VS Code, JetBrains |
| **IDE extension** | `devcontainer.json` should install the extension automatically | VS Code |

### VS Code
In VS Code, both modes work with the sandbox container. The IDE extension runs inside the container and respects the `HTTP_PROXY` environment variable. The [extension](https://marketplace.visualstudio.com/items?itemName=google.gemini-cli-vscode-ide-companion) is automatically installed when using the devcontainer.

## Required Network Policy

The Gemini service requires these services:

```yaml
services:
  - gemini  # Google Gemini API and OAuth domains
```

See the [main README](../../README.md#network-policy) for policy customization and verification.
