# Factory CLI Sandbox Template

Run Factory CLI in a network-locked container. All outbound traffic is routed through an enforcing proxy that blocks requests to domains not on the allowlist.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "factory") and starting the sandbox, authenticate Factory CLI on first run.

### Authenticate Factory (first run only)

Factory CLI supports OAuth authentication. Run the login command inside the container. This typically displays a URL and a code to enter in your browser.

Credentials persist in a Docker volume. You only need to do this once per project.

### Use Factory CLI

Inside the container:

```bash
factory
# or auto-approve mode:
factory --skip-permissions-unsafe
```

Afterward, for CLI mode, stop the container:

```bash
agentbox compose down
```
