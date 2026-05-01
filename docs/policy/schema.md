# Policy Schema

Policy files use the top-level `services` and `domains` fields. The proxy
renders authored policy into one canonical host-record intermediate
representation (IR) before enforcement.

The effective policy location inside the proxy container is `POLICY_PATH`
(defaults to `/etc/mitmproxy/policy.yaml`).

## Authored Format

Simple domain allowlist:

```yaml
services:
  - github

domains:
  - api.anthropic.com
  - "*.example.com"
```

Host entries can also carry request-aware rules:

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

A later policy entry can replace the accumulated record for a host:

```yaml
domains:
  - host: api.github.com
    merge_mode: replace
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          exact: /meta
```

`merge_mode` is authoring-only. It is consumed during rendering and is not kept
in the rendered policy.

## services

`services` is a list of predefined symbolic service names. The renderer
expands each entry into the same canonical host-record intermediate
representation (IR) used for authored `domains` entries, so the proxy runtime
sees one policy shape.

Available services and their expansions are defined in the catalog module at
[images/proxy/service_catalog.py](../../images/proxy/service_catalog.py).
Unknown service names fail rendering immediately.

### String entries

Plain-string `services` entries expand to the service's default set of
catch-all host records:

```yaml
services:
  - github
  - claude
```

### Mapping entries

Mapping entries take a richer shape:

```yaml
services:
  - name: github
    merge_mode: replace
    readonly: true
    repos:
      - owner/repo
    surfaces:
      - api
      - git
```

Supported keys common to every service:

- `name`: required service name; must match a catalog entry.
- `merge_mode`: optional; only `replace` is accepted. When set, the renderer
  discards prior expansions emitted by earlier entries with the same `name`
  before applying the new entry's fragments. `merge_mode` is authoring-only and
  is stripped from the rendered policy.
- `readonly`: optional boolean. `true` narrows emitted rules to read-only
  methods. `false` or omission preserves the service's default readwrite
  behavior. Applied at render time; the matcher is never taught what
  `readonly` means.

For most services, `readonly: true` maps literally to `methods: [GET, HEAD]`.
Git smart-HTTP is the exception (see the GitHub section below).

Unknown keys on a mapping entry fail rendering.

### Merge semantics across entries

- Same-name service entries are additive after expansion by default. Each entry
  expands independently to host-record fragments, and those fragments flow
  through the existing host-level merge path.
- Service option mappings are **not** merged field by field. The renderer does
  not synthesize a combined service config from multiple authored entries.
- `merge_mode: replace` on a service entry discards prior expansions for that
  service name, then applies the new fragments. Authored `domains` entries and
  unrelated services are not affected. After service expansion completes,
  emitted records still participate in `domains`-layer merging, including
  host-level `merge_mode: replace`.

### GitHub service

The GitHub catalog entry supports repo-scoped restriction through two
additional keys:

- `repos`: required when `surfaces` is set. A non-empty list of `owner/name`
  strings. Multi-repo entries expand to linear rule fragments in input order.
  Duplicate repos are deduplicated.
- `surfaces`: required when `repos` is set. A non-empty list naming the
  surfaces to emit rules for. Supported values: `api` (the REST API on
  `api.github.com`) and `git` (Git smart-HTTP on `github.com`).

If neither `repos` nor `surfaces` is set, a mapping entry expands to the same
catch-all host records as the plain-string entry.

`readonly` on the GitHub `api` surface narrows methods literally to
`GET` and `HEAD`. On the `git` surface, `readonly` is semantic enough to
support clone and fetch even though those operations use `POST`:

- `readonly: true` emits repo-scoped rules for
  `info/refs?service=git-upload-pack` (GET, HEAD) and POST to
  `/{owner}/{repo}.git/git-upload-pack`.
- Omitted or `readonly: false` adds the matching `git-receive-pack` discovery
  and POST endpoints used by push.

See [examples/github-repos.yaml](examples/github-repos.yaml) for a focused
repo-scoped policy example.

## domains

`domains` accepts two entry shapes:

- String host entries.
- Mapping entries with `host`, `rules`, and optional `merge_mode`.

### String host entries

String entries define host-wide allow rules:

```yaml
domains:
  - api.openai.com
  - "*.example.com"
```

- Exact host: `api.openai.com`
- Wildcard host: `*.example.com`

Wildcard matching preserves current proxy behavior: `*.example.com` matches both
`example.com` and any subdomain of it.

String entries render to an explicit catch-all rule with `schemes: [http, https]`.

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

- `schemes`
- `methods`
- `path`
- `query`

Rendered rules always include explicit `schemes`. Rendered `methods` is omitted
unless the rule constrains methods.

### schemes

```yaml
schemes: [http, https]
```

- Allowed values: `http`, `https`
- If `schemes` is omitted, the rendered rule gets `schemes: [http, https]`
- Authored scheme values are normalized to lowercase

### methods

```yaml
methods: [GET, POST]
```

- Authored method names are case-insensitive
- Rendered method names are uppercase
- If `methods` is omitted, the rule allows any method

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
- Matching preserves path case. It only canonicalizes URI-equivalent
  percent-encoding forms, such as `%7E` versus `~` and `%2f` versus `%2F`

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
- Query-param names and values remain case-sensitive. Matching happens on the
  decoded query-param map, not on raw escape spelling

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
- string entries become explicit catch-all host records
- `merge_mode` is stripped from the rendered output

## Layered Merge Semantics

In an agentbox runtime, the renderer applies policy inputs in this order:

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

Rendered host records are ordered by match specificity so request evaluation
uses one deterministic precedence model:

- exact host before wildcard host
- among wildcard hosts, longest suffix first

## Enforcement Phases

The proxy enforces policy in two phases. Which phase blocks a given request
depends on the rule fields it uses.

| Rule field    | Enforcement phase   | Notes                                                                              |
|---------------|---------------------|------------------------------------------------------------------------------------|
| `host`        | CONNECT             | Disallowed hosts fail before the TLS tunnel is established                         |
| `schemes`     | CONNECT and Request | HTTPS CONNECT is blocked (`https_not_permitted`) when no rule allows `https`; the decrypted request re-checks `http` vs `https` |
| `methods`     | Request             | Needs the decrypted request                                                        |
| `path`        | Request             | Needs the decrypted request                                                        |
| `query`       | Request             | Needs the decrypted request                                                        |

Host-only rules take the CONNECT fast path: if the requested host has no
matching record, the proxy returns `403` before any TLS handshake completes.

Rules that constrain scheme, method, path, or query require the decrypted
request. For HTTPS, that means the proxy MITMs the connection (the proxy CA
is already installed in the agent image) and evaluates the rule on the real
`Request` object. HTTP requests evaluate the same rules without TLS.

A matched URL rule still implies the endpoint is trusted with the full
request. Header and request-body inspection are out of scope.

## Policy Inputs

The proxy consumes a rendered policy file at `POLICY_PATH`. In normal
agentbox repos, that rendered file is built from these inputs:

1. Active-agent baseline service expansion
2. `.agent-sandbox/policy/user.policy.yaml`
3. `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
4. `.agent-sandbox/policy/policy.devcontainer.yaml` when mounted

You can inspect the effective rendered policy with:

```bash
agentbox policy config
```

The renderer can also be invoked against a single source policy file by
setting `AGENTBOX_POLICY_SOURCE_PATH`. That is mainly useful for tests and
standalone render-policy runs.

The `.agent-sandbox/` directory, and in devcontainer workflows the
`.devcontainer/` directory, are mounted read-only inside the agent container,
preventing the agent from modifying the policy or compose file.

## Reloading Policy

Policy edits take effect on `SIGHUP`. The proxy re-runs `render-policy` in
process, validates the rendered IR, and atomically swaps the matcher. Existing
connections are not interrupted; new requests see the new policy on the next
matcher evaluation.

Trigger a reload from the host:

```bash
agentbox proxy reload
```

A successful reload emits a structured log line through the proxy's stdout
logger:

```json
{"ts": "...", "type": "reload", "action": "applied", "host_records": 7, "exact_host_count": 5, "wildcard_host_count": 2}
```

If the reloaded policy is invalid (missing file, YAML error, schema violation,
or any other exception during render), the prior policy stays active and the
proxy logs a rejection:

```json
{"ts": "...", "type": "reload", "action": "rejected", "error": "..."}
```

Reload is best-effort and does not block traffic. The last-known-good matcher
remains installed until a subsequent reload succeeds. Reload events appear
even when `PROXY_LOG_LEVEL=quiet`.

## Templates And Examples

The base single-source policy template is at
[internal/embeddata/templates/policy.yaml](../../internal/embeddata/templates/policy.yaml).
The layered shared and agent-specific user-owned scaffolds are at
[internal/embeddata/templates/user.policy.yaml](../../internal/embeddata/templates/user.policy.yaml)
and
[internal/embeddata/templates/user.agent.policy.yaml](../../internal/embeddata/templates/user.agent.policy.yaml).
The managed devcontainer policy template is at
[internal/embeddata/templates/policy.devcontainer.yaml](../../internal/embeddata/templates/policy.devcontainer.yaml).

Focused examples:

- [examples/request-rules.yaml](examples/request-rules.yaml) shows method, path, and query constraints.
- [examples/github-repos.yaml](examples/github-repos.yaml) shows repo-scoped GitHub API and Git smart-HTTP access.
- [examples/layered-merge.yaml](examples/layered-merge.yaml) shows additive host merges and `merge_mode: replace`.

For a concise feature tour, see
[What's New In m14: Request-Aware Proxy Rules](../upgrades/m14-request-aware-rules.md).
