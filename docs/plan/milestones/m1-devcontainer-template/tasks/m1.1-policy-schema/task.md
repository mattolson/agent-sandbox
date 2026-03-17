# m1.1-policy-schema

Define the YAML schema for policy files that control network allowlists.

## Goal

Create a policy.yaml format that:
- Groups related domains into "services" with special handling
- Keeps plain "domains" for project-specific additions
- Is simple enough to edit by hand

## Schema Design

```yaml
egress:
  services:
    - claude-code
    - github
    - vscode
  # domains are optional, for project-specific additions
  # domains:
  #   - registry.npmjs.org

# Future sections (not yet implemented):
# ingress:
#   ports: [8080]
# mounts:
#   blocked: [~/.aws/credentials]
```

### Egress Services

| Service | Domains | Resolution |
|---------|---------|------------|
| claude-code | api.anthropic.com, sentry.io, statsig.anthropic.com, statsig.com | DNS resolution |
| github | web, api, git endpoints | Fetches IP ranges from api.github.com/meta, aggregates into CIDR blocks |
| vscode | marketplace.visualstudio.com, mobile.events.data.microsoft.com, vscode.blob.core.windows.net, update.code.visualstudio.com | DNS resolution |

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| egress.services | list of strings | No | Known services with predefined domain lists |
| egress.domains | list of strings | No | Additional domains to allow (DNS resolution at startup) |

## Deliverables

- [x] `docs/policy/schema.md` - Schema documentation
- [x] `docs/policy/example.yaml` - Example policy file with comments

## Out of Scope

- Firewall script changes (m1.4)
- Path/method filtering (m14)
- JSON Schema for IDE validation

## Status

Complete. Schema documented, example created. Ready for m1.4 to implement firewall parsing.
