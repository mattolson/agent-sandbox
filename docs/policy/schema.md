# Policy Schema

Policy files configure which domains the sandbox can reach. The proxy enforcer reads this file at startup and blocks requests to any domain not on the allowlist.

Policy file location: `/etc/mitmproxy/policy.yaml` (inside the proxy container).

## Format

```yaml
services:
  - github

domains:
  - api.anthropic.com
  - "*.example.com"
```

## services

A list of predefined service names. Each service expands to a set of domain patterns.

| Service | Domains |
|---------|---------|
| `github` | `github.com`, `*.github.com`, `githubusercontent.com`, `*.githubusercontent.com` |
| `claude` | `*.anthropic.com`, `*.claude.ai`, `*.claude.com` |
| `copilot` | `github.com`, `api.github.com`, `copilot-telemetry.githubusercontent.com`, `collector.github.com`, `default.exp-tas.com`, `copilot-proxy.githubusercontent.com`, `origin-tracker.githubusercontent.com`, `*.githubcopilot.com`, `*.individual.githubcopilot.com`, `*.business.githubcopilot.com`, `*.enterprise.githubcopilot.com`, `*.githubassets.com` |
| `vscode` | `update.code.visualstudio.com`, `marketplace.visualstudio.com`, `mobile.events.data.microsoft.com`, `main.vscode-cdn.net`, `*.vsassets.io` |
| `jetbrains` | `plugins.jetbrains.com`, `downloads.marketplace.jetbrains.com` |
| `jetbrains-ai` | `api.jetbrains.ai`, `api.app.prod.grazie.aws.intellij.net`, `www.jetbrains.com`, `account.jetbrains.com`, `oauth.account.jetbrains.com`, `frameworks.jetbrains.com`, `cloudconfig.jetbrains.com`, `download.jetbrains.com`, `download-cf.jetbrains.com`, `download-cdn.jetbrains.com`, `resources.jetbrains.com`, `cdn.agentclientprotocol.com` |

Services are defined as a static mapping in the proxy enforcer addon (`images/proxy/addons/enforcer.py`). To add a new service, add an entry to the `SERVICE_DOMAINS` dict.

## domains

A list of domain names to allow. Supports two formats:

- **Exact match**: `api.anthropic.com` allows only that exact hostname
- **Wildcard prefix**: `*.example.com` allows any subdomain of example.com (but not example.com itself)

Use this for:
- Agent API endpoints (e.g., api.anthropic.com for Claude Code)
- Package registries (e.g., registry.npmjs.org, pypi.org)
- Internal APIs your project needs

## How enforcement works

The proxy sidecar (mitmproxy) runs in one of two modes, controlled by the `PROXY_MODE` environment variable:

- **enforce** (default in templates): loads the policy file, blocks non-matching requests with HTTP 403
- **log**: allows all traffic, logs requests to stdout as JSON

When a request arrives:
1. For HTTPS: the proxy intercepts the CONNECT tunnel and checks the target hostname
2. For HTTP: the proxy checks the Host header in the request
3. If the hostname matches an allowed domain (exact or wildcard), the request proceeds
4. If not, the proxy returns `403 Blocked by proxy policy: <hostname>`

All requests are logged to stdout as JSON with an `"action"` field of `"allowed"` or `"blocked"`.

If `PROXY_MODE=enforce` and no policy file exists at `/etc/mitmproxy/policy.yaml`, the proxy refuses to start.

## Where policy files live

There are two places a policy can come from:

1. **Baked into the proxy image** at build time (`images/proxy/policy.yaml`). The default blocks all traffic.
2. **Generated per-project** by `agentbox init`, which creates a policy file at `.agent-sandbox/policy-<mode>-<agent>.yaml` and mounts it into the proxy container.

The `agentbox init` command adds a volume mount to the proxy service in the generated compose file:

```yaml
# Under proxy.volumes (added by agentbox init):
- <path-to-policy>:/etc/mitmproxy/policy.yaml:ro
```

The `.agent-sandbox/` directory (CLI mode) or `.devcontainer/` directory (devcontainer mode) is mounted read-only inside the agent container, preventing the agent from modifying the policy or compose file. The proxy only reads the policy at startup, so changes require a human-initiated restart.

## Examples

The base policy template is at [cli/templates/policy.yaml](../../cli/templates/policy.yaml). The `agentbox init` command copies this template and populates it with the services appropriate for the selected agent and IDE.
