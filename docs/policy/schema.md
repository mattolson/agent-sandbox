# Policy Schema

Policy files configure which domains the sandbox can reach. The proxy enforcer reads the rendered effective policy at startup and blocks requests to any domain not on the allowlist.

Effective policy location inside the proxy container: `POLICY_PATH` (defaults to `/etc/mitmproxy/policy.yaml` for
single-file setups).

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

Services are defined as a static mapping in the proxy enforcer addon. See the `SERVICE_DOMAINS` dict in [`images/proxy/addons/enforcer.py`](../../images/proxy/addons/enforcer.py) for the up-to-date list of all available services and the domains they expand to. To add a new service, add an entry to this dictionary.

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

If `PROXY_MODE=enforce` and no effective policy file exists at `POLICY_PATH`, the proxy refuses to start.

## Where policy files live

There are three ways a policy can be sourced:

1. **Baked into the proxy image** at build time (`images/proxy/policy.yaml`). The default blocks all traffic.
2. **Single-file project policy** for legacy layouts. `agentbox init` used to create `.agent-sandbox/policy-<mode>-<agent>.yaml` and mount it into the proxy container at `/etc/mitmproxy/policy.yaml`.
3. **Layered project policy inputs** for current CLI and managed devcontainer file layouts:
   - `.agent-sandbox/policy/user.policy.yaml`
   - `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
   - `.agent-sandbox/policy/policy.devcontainer.yaml` (managed devcontainer layer only)

For layered projects, proxy startup renders the effective policy from:

1. the active agent baseline (`services: [<active-agent>]`)
2. `.agent-sandbox/policy/user.policy.yaml`
3. `.agent-sandbox/policy/user.agent.<active-agent>.policy.yaml`
4. `.agent-sandbox/policy/policy.devcontainer.yaml` when the devcontainer compose overlay mounts it

The layered merge semantics are intentionally narrow:

- `services`: union with stable order and de-duplication
- `domains`: union with stable order and de-duplication
- other mapping keys: deep-merged when both sides are maps
- other lists and scalars: later layers replace earlier ones

The rendered result is then used for enforcement. You can inspect that rendered output with:

```bash
agentbox policy config
```

Historical single-file layouts mounted the policy directly into the proxy service:

```yaml
# Under proxy.volumes (added by agentbox init):
- <path-to-policy>:/etc/mitmproxy/policy.yaml:ro
```

Current `agentbox` commands no longer treat that layout as a supported editing or runtime surface. If those files are
still present in your project, rename them out of the way and follow
[docs/upgrades/m8-layered-layout.md](../upgrades/m8-layered-layout.md).

Layered CLI layouts mount the shared and agent-specific `.agent-sandbox/policy/` input files into fixed proxy paths
instead of replacing `/etc/mitmproxy/policy.yaml` directly. Managed devcontainer layouts mount those same
`.agent-sandbox/policy/` files plus the managed devcontainer policy layer.

The `.agent-sandbox/` directory, and in devcontainer workflows the `.devcontainer/` directory, are mounted read-only
inside the agent container, preventing the agent from modifying the policy or compose file. The proxy only reads the
effective policy at startup, so changes require a human-initiated restart.

## Examples

The single-file base policy template is at [cli/templates/policy.yaml](../../cli/templates/policy.yaml). Layered shared
and agent-specific user-owned scaffolds are at [cli/templates/user.policy.yaml](../../cli/templates/user.policy.yaml)
and [cli/templates/user.agent.policy.yaml](../../cli/templates/user.agent.policy.yaml). The managed devcontainer policy
template is at [cli/templates/policy.devcontainer.yaml](../../cli/templates/policy.devcontainer.yaml).
