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
| `claude` | `*.anthropic.com`, `*.claude.ai`, `*.claude.com`, `*.sentry.io`, `*.datadoghq.com` |
| `vscode` | `update.code.visualstudio.com`, `marketplace.visualstudio.com`, `mobile.events.data.microsoft.com`, `main.vscode-cdn.net`, `*.vsassets.io` |

Services are defined as a static mapping in the proxy enforcer addon (`images/proxy/addons/enforcer.py`). To add a new service, add an entry to the `SERVICE_DOMAINS` dict.

## domains

A list of domain names to allow. Supports two formats:

- **Exact match**: `api.anthropic.com` allows only that exact hostname
- **Wildcard suffix**: `*.example.com` allows any subdomain of example.com (but not example.com itself)

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
2. **Mounted from the host** at runtime, overriding the baked-in default.

To mount a custom policy in docker-compose.yml:

```yaml
# Under proxy.volumes:
- ${HOME}/.config/agent-sandbox/policy.yaml:/etc/mitmproxy/policy.yaml:ro
```

The policy file must live outside the workspace. If it were inside, the agent could modify its own allowlist.

## Examples

See [examples/](./examples/) for ready-to-use policy files.

- [claude.yaml](./examples/claude.yaml) - Claude Code (GitHub + Anthropic API)
