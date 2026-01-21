# Policy Schema

Policy files configure sandbox restrictions for agent-sandbox containers. Currently supports outbound network allowlists, with future support planned for ingress rules, port forwarding, and mount restrictions.

## Format

```json
{
  "services": ["github"],
  "domains": [
    "registry.npmjs.org",
    "your-internal-api.example.com"
  ]
}
```

## Services

A list of predefined service names. Each service expands to a set of IPs with appropriate resolution logic.

| Service | Description | Notes |
|---------|-------------|-------|
| `github` | GitHub web, API, and git endpoints | IPs fetched from api.github.com/meta and aggregated into CIDR blocks |

## Domains

A list of additional domain names to allow. Each domain is resolved via DNS at container startup, and the resulting IPs are added to the allowlist.

Use this for:
- Package registries (e.g., registry.npmjs.org, pypi.org)
- Internal APIs your project needs
- Claude Code endpoints (api.anthropic.com, sentry.io, etc.)
- VS Code endpoints (marketplace.visualstudio.com, etc.)

## Examples

### Minimal policy (GitHub only)

```json
{
  "services": ["github"],
  "domains": []
}
```

### Claude Code agent

```json
{
  "services": ["github"],
  "domains": [
    "api.anthropic.com",
    "sentry.io",
    "statsig.anthropic.com",
    "statsig.com"
  ]
}
```

### With VS Code devcontainer support

```json
{
  "services": ["github"],
  "domains": [
    "api.anthropic.com",
    "sentry.io",
    "statsig.anthropic.com",
    "statsig.com",
    "marketplace.visualstudio.com",
    "mobile.events.data.microsoft.com",
    "vscode.blob.core.windows.net",
    "update.code.visualstudio.com"
  ]
}
```

### Adding project-specific domains

```json
{
  "services": ["github"],
  "domains": [
    "api.anthropic.com",
    "sentry.io",
    "statsig.anthropic.com",
    "statsig.com",
    "api.stripe.com",
    "pypi.org",
    "registry.npmjs.org"
  ]
}
```

## How It Works

At container startup, `init-firewall.py` reads the policy file and:

1. For the `github` service, fetches IP ranges from api.github.com/meta and aggregates them
2. For each domain in `domains`, performs DNS resolution
3. Adds all IPs to an ipset
4. Configures iptables to allow only traffic to IPs in the set
5. Verifies the firewall by checking that example.com is blocked

Changes to the policy require rebuilding the container.
