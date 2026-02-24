# OpenAI Codex CLI Sandbox Template

Run OpenAI Codex CLI in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "codex") and starting the sandbox, authenticate Codex on first run.

### Authenticate Codex (first run only)

Two authentication methods are supported:

**API key** (simplest): Set the `OPENAI_API_KEY` environment variable before starting the container, or export it inside the container shell.

**Device code OAuth**: Run `codex login` inside the container. This displays a URL and a code to enter in your browser. No localhost callback is needed, so it works from inside the sandbox.

Device code OAuth requires enabling "Enable device code authorization for Codex" in your [ChatGPT workspace settings](https://platform.openai.com/settings). The login flow will tell you if this is not yet enabled.

Credentials persist in a Docker volume. You only need to do this once per project.

### Use Codex CLI

Inside the container:

```bash
codex
# or auto-approve mode:
codex --full-auto
```

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```

## Required Network Policy

The Codex service requires these services:

```yaml
services:
  - codex  # OpenAI API and OAuth domains
```

See the [main README](../../README.md#network-policy) for policy customization and verification.
