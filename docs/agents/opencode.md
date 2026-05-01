# OpenCode Sandbox Template

Run OpenCode in a network-locked container. All outbound traffic is routed through an enforcing proxy that applies the project's network policy.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "opencode") and starting the sandbox, configure your provider.

### Provider configuration

OpenCode is provider-agnostic. It supports many LLM providers (Anthropic, OpenAI, Google, and others) via API keys. You choose which provider to use at runtime.

Because the sandbox proxy only allows traffic declared in policy, you must add the appropriate provider service to your network policy. For example, to use OpenCode with Anthropic:

```yaml
# .agent-sandbox/policy/user.agent.opencode.policy.yaml
services:
  - claude
```

Or to use OpenCode with OpenAI:

```yaml
services:
  - codex
```

Available provider services: `claude` (Anthropic), `codex` (OpenAI), `gemini` (Google), `copilot` (GitHub Copilot).

Edit the policy with `agentbox edit policy`; active-policy changes hot-reload automatically when the proxy is running.

### Authenticate (first run only)

Set the provider's API key environment variable before starting the container, or export it inside the container shell:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
opencode
```

Credentials persist in a Docker volume (`~/.config/opencode`). You only need to do this once per project.

### Use OpenCode

Inside the container:

```bash
opencode
```

The sandbox image includes a baked config that grants all tool permissions (yolo mode). OpenCode uses a config-based permission system rather than a CLI flag.

### Sandbox environment

The image sets these environment variables to prevent network calls that would be blocked by the proxy:

- `OPENCODE_DISABLE_AUTOUPDATE=true` — prevents update checks
- `OPENCODE_DISABLE_LSP_DOWNLOAD=true` — prevents LSP binary downloads

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```
