# What's New In m14: Request-Aware Proxy Rules

`m14` extends proxy enforcement from host-only allowlists to request-aware rules that can constrain scheme, method,
path, and query parameters. This is a feature-tour, not a destructive migration — **your existing policies continue
to work unchanged**.

If you authored a policy against `m13` or earlier, you do not need to edit anything. Host-only `domains` entries and
plain-string `services` still render to the same CONNECT fast path they always did.

## What you get in m14

- **Request-aware rules.** `domains` entries now accept a `rules` list where each rule can constrain `schemes`,
  `methods`, `path`, and `query`. Matching is an allow-only conjunction; a request passes if it matches any allowed
  rule for its host.
- **Semantic service catalog.** Service entries can take mapping form with options like `readonly: true` or, for the
  GitHub catalog entry, `repos: [...]` and `surfaces: [api, git]`. The catalog expands to the same rule IR the
  matcher already consumes — no per-service branches live in the enforcer.
- **Hot reload.** `agentbox proxy reload` sends `SIGHUP` to the proxy. The addon re-runs `render-policy` in process,
  validates the rendered IR, and atomically swaps the matcher. A bad reload keeps the last-known-good matcher
  active and logs a structured rejection event.
- **Layered merge semantics.** Host records merge by normalized host identity across shared, agent-specific, and
  devcontainer layers. `merge_mode: replace` on a host record discards prior same-host records before applying the
  later one.

## Backward compatibility guarantee

`m14` preserves these properties of the pre-m14 proxy:

- Plain-string `domains` entries render to an explicit catch-all rule with `schemes: [http, https]` and are blocked
  or allowed at CONNECT before the TLS tunnel is established.
- Plain-string `services` entries expand to the same catch-all host records they did before.
- The rendered host records are ordered exact-host-first, then by longest wildcard suffix. Host specificity wins;
  rule evaluation is deterministic.
- The proxy sidecar is still the single enforcement point. No second policy renderer exists.

If a policy validated under `m13` renders under `m14` to the same effective set of hosts, the runtime decisions are
identical.

## Adopting the new authoring surfaces

None of the following is required. Adopt what fits your project.

### Constrain a specific endpoint

```yaml
domains:
  - host: api.example.com
    rules:
      - methods: [GET]
        path:
          prefix: /v1/public/
```

See [docs/policy/examples/request-rules.yaml](../policy/examples/request-rules.yaml) for a minimal request-aware
example.

### Restrict a service by repo

```yaml
services:
  - name: github
    readonly: true
    repos:
      - owner/repo
    surfaces: [api, git]
```

See [docs/policy/examples/github-repos.yaml](../policy/examples/github-repos.yaml).

### Replace a lower layer's host

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

See [docs/policy/examples/layered-merge.yaml](../policy/examples/layered-merge.yaml).

## Which phase enforces which rule

Host-only matches enforce at CONNECT; everything else enforces at request time after TLS decryption. See the
"Enforcement Phases" table in [docs/policy/schema.md](../policy/schema.md#enforcement-phases) for the full mapping.

The practical consequence: a disallowed host is rejected before any bytes of HTTP flow. A rule with `methods: [GET]`
has to wait until the request line is parsed, because "this is a POST" is not visible at CONNECT time.

## Reloading policy without restart

Edit a user-owned policy file under `.agent-sandbox/policy/`, then:

```bash
agentbox proxy reload
```

Successful reload emits:

```json
{"ts": "...", "type": "reload", "action": "applied", "host_records": N, "exact_host_count": X, "wildcard_host_count": Y}
```

A rejected reload emits `"action": "rejected"` with an `error` field and keeps the previous policy active. See
[docs/troubleshooting.md](../troubleshooting.md#policy-reload-rejected) for diagnosis.

## What's out of scope in m14

- Header matching and request-body inspection. A matched URL rule still implies trust in the endpoint for headers
  and body.
- Request or response mutation.
- Non-HTTP protocols.
- GitHub REST wrapper work (tracked for `m15`).
- Secret injection or credential features (tracked for `m16`).
