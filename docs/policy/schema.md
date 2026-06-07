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

Mapping entries take a richer shape. The GitHub catalog accepts repo-scoped
options; see [GitHub service](#github-service) for the full set.

```yaml
services:
  - name: github
    merge_mode: replace
    repos:
      - owner/repo
    git:
      access: read
    api:
      access: read
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

A repo-scoped GitHub entry names one or more repositories and configures the
`git` smart-HTTP surface, the `api` REST surface, or both. Each surface is its
own mapping with an `access` level and optional `auth` block.

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: read
      auth:
        secret: github.owner.repo.read-token
    api:
      access: read
```

Repo-scoped keys:

- `repos`: required when `git` or `api` is set. A non-empty list of `owner/name`
  strings. Multi-repo entries expand to linear rule fragments in input order.
  Duplicate repos are deduplicated.
- `git`: optional mapping. Configures the Git smart-HTTP surface on
  `github.com` for the listed repos.
- `api`: optional mapping. Configures the REST API surface on
  `api.github.com` for the listed repos.

At least one of `git` or `api` must be present when `repos` is set.

Repo names are normalized to lowercase, and the generated repo path rules are
matched **case-insensitively** on the owner/repo segment. GitHub treats
owner/repo as case-insensitive, so a clone or API call using the repository's
canonical mixed case (for example `RyanLisse/Vitalink`) matches an entry
authored in any case. This case-insensitivity is scoped to the GitHub repo
rules; all other path matching remains case-sensitive per RFC 3986.

Surface mapping keys:

- `access`: required. One of `read` or `readwrite`.
- `auth`: optional. Supported on `git` only; rejected on `api` in this
  milestone.

On the `api` surface, `access: read` narrows methods to `GET` and `HEAD`. On
the `git` surface, `access` is semantic enough to keep clone and fetch working
even though they use `POST`:

- `access: read` emits repo-scoped rules for
  `info/refs?service=git-upload-pack` (GET, HEAD) and POST to
  `/{owner}/{repo}.git/git-upload-pack`.
- `access: readwrite` adds the matching `git-receive-pack` discovery and POST
  endpoints used by push.

The `git.auth` mapping configures proxy-side credential injection for the
emitted Git rules. See [Request transforms](#request-transforms) for the
underlying mechanism.

```yaml
git:
  access: readwrite
  auth:
    secret: github.owner.repo.push-token
    client_shim:
      kind: git-askpass
```

`git.auth` keys:

- `secret`: required. A secret ID (see
  [Request transforms](#request-transforms) for grammar). The renderer
  attaches an `Authorization: Basic` header with username `x-access-token`
  and the resolved secret as the password to every Git rule in this entry.
- `client_shim`: optional. When present, the only supported shape is
  `kind: git-askpass`. The renderer switches the emitted Git rules from
  `on_existing_header: fail` to `on_existing_header: replace` and adds a
  renderer-owned `credential_shim` block to the rendered policy. The agent
  container sources the rendered shim to export `GIT_ASKPASS`,
  `AGENTBOX_GIT_FAKE_USERNAME`, `AGENTBOX_GIT_FAKE_PASSWORD`, and
  `GIT_TERMINAL_PROMPT=0`, so `git push` non-interactively supplies a
  placeholder credential that the proxy replaces with the real secret.

`git.auth` is required when `git.access` is `readwrite`. Without `client_shim`,
a `readwrite` flow still injects the real secret, but any pre-existing
`Authorization` header on a matched request fails closed at the proxy.

Rejected legacy fields on a GitHub mapping entry (renderer fails with a
descriptive error):

- `surfaces`: use `git` and `api` mappings instead.
- Top-level `access` or `auth`: nest them inside `git` or `api`.
- `readonly` on a repo-scoped entry: use `access: read` or `access: readwrite`
  on each surface mapping. `readonly` is still accepted on a non-repo-scoped
  mapping entry as a way to narrow the catch-all GitHub records.

If neither `repos`, `git`, nor `api` is set, a mapping entry expands to the
same catch-all host records as the plain-string entry, optionally narrowed by
`readonly: true`.

Focused examples under `docs/policy/examples/`:

- [github-private-git.yaml](examples/github-private-git.yaml) - private read
  with `git.auth.secret`.
- [github-git-push.yaml](examples/github-git-push.yaml) - readwrite with the
  `git-askpass` client shim.
- [github-repos.yaml](examples/github-repos.yaml) - mixed `git` and `api`
  surfaces for a repo-scoped policy.

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

## Request transforms

A `domains[]` mapping entry can attach a host-scoped request transform that
injects one or more headers into every matched request:

```yaml
domains:
  - host: api.example.com
    transform:
      request:
        headers:
          Authorization:
            secret: service-token
            transform:
              type: bearer
        on_existing_header: fail
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          prefix: /v1/
```

The renderer attaches the transform to every rule under the host; rule-level
`transform` is not an authoring surface.

`transform.request` keys:

- `headers`: required non-empty mapping from header name to header
  configuration. Header names follow the HTTP token grammar and are matched
  case-insensitively against any pre-existing request header.
- `on_existing_header`: optional; one of `fail` (default) or `replace`. `fail`
  blocks the request before it reaches the upstream when the header is already
  set. `replace` overwrites the existing value with the rendered one.

Each header configuration takes two keys:

- `secret`: required secret ID. Must match `[A-Za-z0-9._-]+`. Literal `.`
  and `..` are rejected. The proxy resolves the secret from its configured
  backend at request time. See [secrets.md](../secrets.md) for the backing
  storage layout, freshness contract, and non-goals.
- `transform`: required mapping describing how to render the resolved secret
  into the header value.

Supported `transform.type` values:

- `bearer`: emits `Bearer <secret>`. No other keys.
- `basic`: emits `Basic base64(username:secret)`. Requires `username`. The
  username must not contain control characters or `:`.

See [examples/request-transform.yaml](examples/request-transform.yaml) for
a focused example of host-scoped `transform.request` outside the service
catalog.

Request-aware enforcement: when a rule carries a request transform, the proxy
forces request inspection at CONNECT time for HTTPS and stages every header
value before mutating the flow. A failed secret resolution or
`on_existing_header: fail` conflict blocks the request before any bytes reach
the upstream.

`transform.response` is reserved for future use. Setting `response` to a
non-empty value fails rendering today.

### Renderer-owned fields

`credential_shim` is rejected at the top level of a source policy file.
Authored top-level `credential_shim` blocks fail rendering with
`credential_shim is renderer-owned and cannot be authored in policy files`.

The renderer emits the same key in its **output** when a service catalog
entry (currently only `services[].git.auth.client_shim`) requests an
agent-side shim. The rendered payload is intentionally narrow:

```yaml
credential_shim:
  version: 1
  hints:
    - service: github
      surface: git
      kind: git-askpass
      host: github.com
      username: x-access-token
      fake_password: agentbox-proxy-managed
      secrets:
        - github.owner.repo.push-token
```

- `version`: schema version, always `1` today.
- `hints[]`: one entry per shim. The agent container's
  `/etc/agent-sandbox/shell-init.sh` reads the rendered init fragment and
  exports the corresponding env vars (`GIT_ASKPASS`,
  `AGENTBOX_GIT_FAKE_USERNAME`, `AGENTBOX_GIT_FAKE_PASSWORD`,
  `GIT_TERMINAL_PROMPT=0` for `kind: git-askpass`).
- `fake_password`: a placeholder value. The proxy replaces it with the
  resolved real secret on every matched request before the upstream sees
  the header.

The rendered `credential_shim` block contains no resolved secret values.
Real values stay on the host secret directory and are never read into the
rendered policy.

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
| `transform`   | CONNECT and Request | A rule with `transform.request` forces request inspection at CONNECT for HTTPS; header staging and injection happen on the decrypted request |

Host-only rules take the CONNECT fast path: if the requested host has no
matching record, the proxy returns `403` before any TLS handshake completes.

Rules that constrain scheme, method, path, or query require the decrypted
request. For HTTPS, that means the proxy MITMs the connection (the proxy CA
is already installed in the agent image) and evaluates the rule on the real
`Request` object. HTTP requests evaluate the same rules without TLS.

A matched URL rule still implies the endpoint is trusted with the full
request. The proxy injects request headers when a rule's `transform.request`
declares one (see [Request transforms](#request-transforms)); it does not
inspect request bodies, response bodies, or arbitrary URLs for leaked secret
values.

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

## Agent-Visible Effective Policy

At startup the proxy also writes a sanitized copy of the rendered allowlist to a
shared volume that the agent container mounts read-only at
`/run/agentbox/policy.yaml`. This lets an agent discover exactly which hosts it
can reach without host-side tooling.

The export is whitelist-sanitized: it contains only `domains` with each host's
`schemes`, `methods`, `path`, and `query` matchers. The renderer-owned
`credential_shim` payload and per-rule `transform` directives — both of which can
reference secret IDs — are stripped, as are any other top-level fields. It is
rewritten on proxy restart and on each successful hot reload (`SIGHUP`), so it
stays in sync with the policy in force.

The `operating-in-agent-sandbox` skill teaches agents to read this file.

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
- [examples/github-private-git.yaml](examples/github-private-git.yaml) shows a private read with `git.auth.secret`.
- [examples/github-git-push.yaml](examples/github-git-push.yaml) shows a readwrite push flow with the `git-askpass` client shim.
- [examples/request-transform.yaml](examples/request-transform.yaml) shows host-scoped header injection with a `bearer` transform.
- [examples/layered-merge.yaml](examples/layered-merge.yaml) shows additive host merges and `merge_mode: replace`.

For a concise feature tour, see
[What's New In m14: Request-Aware Proxy Rules](../upgrades/m14-request-aware-rules.md).
