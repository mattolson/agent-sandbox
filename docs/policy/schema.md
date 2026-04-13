# Policy Schema

Policy files still use the existing top-level `services` and `domains` fields.
`m14.1` keeps that authored surface backward compatible, but the proxy now
renders it into one canonical host-record intermediate representation (IR)
before enforcement.

Effective policy location inside the proxy container: `POLICY_PATH` (defaults to
`/etc/mitmproxy/policy.yaml` for single-file setups).

## Authored Format

Simple host-only authoring still works:

```yaml
services:
  - github

domains:
  - api.anthropic.com
  - "*.example.com"
```

Rich host entries can carry request-aware rules:

```yaml
domains:
  - host: api.github.com
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          prefix: /repos/example/
        query:
          exact: {}
```

Later policy layers can replace the accumulated record for a host:

```yaml
domains:
  - host: api.github.com
    merge_mode: replace
    rules:
      - scheme: https
        method: get
        path:
          exact: /meta
```

`merge_mode` is authoring-only. It is consumed during rendering and is not kept
in the rendered policy.

## services

`services` is still a list of predefined symbolic service names. The renderer
expands them into the same canonical host-record intermediate representation
(IR) used for authored `domains` entries, so the proxy runtime sees one policy
shape.

Available services are defined in
[images/proxy/render-policy](../../images/proxy/render-policy).

For `m14.1`, `services` entries are still plain strings only. Rich
service-specific option schemas are deferred to `m14.3`.

Unknown service names fail rendering immediately.

## domains

`domains` now accepts two entry shapes:

- String host entries.
- Mapping entries with `host`, `rules`, and optional `merge_mode`.

### String host entries

String entries preserve the legacy host-only path:

```yaml
domains:
  - api.openai.com
  - "*.example.com"
```

- Exact host: `api.openai.com`
- Wildcard host: `*.example.com`

Wildcard matching preserves current proxy behavior: `*.example.com` matches both
`example.com` and any subdomain of it.

String entries render to an explicit catch-all rule with
`schemes: [http, https]`.

### Mapping host entries

Mapping entries use this authored shape:

```yaml
domains:
  - host: api.github.com
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          prefix: /repos/example/
```

Supported keys:

- `host`: required exact or wildcard host pattern
- `rules`: required non-empty list of request rules
- `merge_mode`: optional; the only supported value is `replace`

Unknown keys fail rendering.

## Rule Format

Rules are allow-only conjunctions. Each rule may constrain:

- `scheme` or `schemes`
- `method` or `methods`
- `path`
- `query`

Rendered rules always include explicit `schemes`. Rendered `methods` is omitted
unless the rule constrains methods.

### schemes

`scheme` is a singular shorthand for `schemes`.

```yaml
scheme: https
schemes: [http, https]
```

- Allowed values: `http`, `https`
- If neither form is present, the rendered rule gets `schemes: [http, https]`
- If both forms are present, the renderer warns on `stderr`, merges them,
  normalizes to lowercase, and de-duplicates them

### methods

`method` is a singular shorthand for `methods`.

```yaml
method: get
methods: [GET, POST]
```

- Authored method names are case-insensitive
- Rendered method names are uppercase
- If neither form is present, the rule allows any method
- If both forms are present, the renderer warns on `stderr`, merges them, and
  de-duplicates them

### path

`path` is an optional mapping with exactly one matcher:

```yaml
path:
  exact: /meta
```

```yaml
path:
  prefix: /repos/example/
```

- Supported matchers: `exact`, `prefix`
- Path values must start with `/`
- A rule may carry at most one path matcher

### query

`query` currently supports exact matching only:

```yaml
query:
  exact: {}
```

```yaml
query:
  exact:
    ref: docs
    tag: [one, two]
```

- Omitted `query` means the rule does not constrain the query string
- `query.exact: {}` means the request must have no query params
- Scalar values normalize to single-item lists in the rendered policy
- Rendered `query.exact` keys are sorted for determinism

## Rendered Policy Intermediate Representation (IR)

The renderer compiles authored `services` and `domains` into one canonical
intermediate representation (IR):

```yaml
domains:
  - host: api.github.com
    rules:
      - schemes:
          - https
        methods:
          - GET
        path:
          prefix: /repos/example/
        query:
          exact: {}

  - host: "*.example.com"
    rules:
      - schemes:
          - http
          - https
```

Rendered policy characteristics:

- `services` is compiled away
- every rendered `domains` entry is a mapping with `host` and `rules`
- legacy string entries become explicit catch-all host records
- `merge_mode` is stripped from the rendered output

## Layered Merge Semantics

For layered CLI and managed devcontainer layouts, the renderer applies layers in
this order:

1. Active-agent baseline service expansion (`services: [<active-agent>]`)
2. `.agent-sandbox/policy/user.policy.yaml`
3. `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
4. `.agent-sandbox/policy/policy.devcontainer.yaml` when mounted

Merge behavior:

- Host records merge by normalized `host` identity, not list position
- Default same-host behavior is additive rule merge with stable order and
  de-duplication of equivalent normalized rules
- `merge_mode: replace` discards the earlier same-host record before applying
  the later one
- Different host identities coexist in the rendered policy

Rendered host records are ordered by match specificity so later request-aware
evaluation has one deterministic precedence model:

- exact host before wildcard host
- among wildcard hosts, longest suffix first

## Enforcement Status

`m14.1` stabilizes the authored schema, validation, layering, and rendered
intermediate representation (IR). It does **not** yet ship request-phase
enforcement for `methods`, `path`, or `query`.

Current runtime behavior remains host-oriented:

- The proxy uses the rendered host records for allowlist decisions
- Legacy host-only policies continue to work
- Request-aware rule fields are rendered and validated now so `m14.2` can
  consume one stable policy shape

For `m14`, a matched URL rule still implies that the endpoint is trusted with
the full request. Header and request-body inspection remain out of scope.

## Where Policy Files Live

There are three ways a policy can be sourced:

1. Baked into the proxy image at build time (`images/proxy/policy.yaml`)
2. Single-file project policy for legacy layouts
3. Layered project policy inputs for current CLI and managed devcontainer file
   layouts:
   - `.agent-sandbox/policy/user.policy.yaml`
   - `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
   - `.agent-sandbox/policy/policy.devcontainer.yaml` (managed devcontainer
     layer only)

For layered projects, the proxy renders the effective policy at startup from
the active agent baseline plus those user-owned inputs. You can inspect that
rendered output with:

```bash
agentbox policy config
```

The `.agent-sandbox/` directory, and in devcontainer workflows the
`.devcontainer/` directory, are mounted read-only inside the agent container,
preventing the agent from modifying the policy or compose file.

## Examples

The single-file base policy template is at
[internal/embeddata/templates/policy.yaml](../../internal/embeddata/templates/policy.yaml).
Layered shared and agent-specific user-owned scaffolds are at
[internal/embeddata/templates/user.policy.yaml](../../internal/embeddata/templates/user.policy.yaml)
and
[internal/embeddata/templates/user.agent.policy.yaml](../../internal/embeddata/templates/user.agent.policy.yaml).
The managed devcontainer policy template is at
[internal/embeddata/templates/policy.devcontainer.yaml](../../internal/embeddata/templates/policy.devcontainer.yaml).
