# Pi Coding Agent Sandbox Template

Run Pi coding agent in a network-locked container. All outbound traffic is routed through an enforcing proxy that applies the project's network policy.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "pi") and starting the sandbox, authenticate Pi on first run.

### Provider configuration

Pi is provider-agnostic. It supports many LLM providers (Anthropic, OpenAI, Google, Mistral, etc.) via API keys or OAuth subscriptions. You choose which provider to use at runtime.

Because the sandbox proxy only allows traffic declared in policy, you must add the appropriate provider service to your network policy. For example, to use Pi with Anthropic:

```yaml
# .agent-sandbox/policy/user.agent.pi.policy.yaml
services:
  - claude
```

Or to use Pi with OpenAI:

```yaml
services:
  - codex
```

Available provider services: `claude` (Anthropic), `codex` (OpenAI), `gemini` (Google), `copilot` (GitHub Copilot).

Edit the policy with `agentbox edit policy`; active-policy changes hot-reload automatically when the proxy is running.

### Authenticate Pi (first run only)

**API key** (simplest): Set the provider's API key environment variable before starting the container, or export it inside the container shell:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
pi
```

**OAuth subscription**: Use the `/login` command inside Pi to authenticate with a subscription provider (Claude Pro/Max, ChatGPT Plus/Pro, GitHub Copilot, Google Gemini CLI).

Credentials persist in a Docker volume (`~/.pi`). You only need to do this once per project.

### Use Pi

Inside the container:

```bash
pi
```

Pi has no built-in permission system, so it runs in auto-approve mode by default.

### Pi packages

Pi's `pi install` and `pi update` commands fetch packages from the npm registry. If you need this, add `registry.npmjs.org` to your policy domains:

```yaml
domains:
  - registry.npmjs.org
```

This is not included by default because it is not required for Pi's core operation.

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```
