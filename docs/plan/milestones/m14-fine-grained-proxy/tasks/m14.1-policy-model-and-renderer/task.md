# Task: m14.1 - Policy Model and Renderer

## Summary

Define and implement a canonical request-aware policy model that supports deterministic layered merges without breaking
existing `services` plus string `domains` policies.

## Scope

- Decide the canonical YAML shape for rich domain entries and nested request rules
- Extend `images/proxy/render-policy` validation and normalization to accept both legacy string domains and new
  rule-bearing entries
- Preserve the current layered policy inputs and single render path inside the proxy
- Define deterministic merge identity for rich domain entries across shared, agent-specific, and devcontainer layers
- Update schema docs and examples so the new format is reviewable and not guesswork
- If the rendered format changes materially, make the minimum downstream parser changes needed so `m14.2` can consume
  the new policy IR without splitting parsing across tasks

## Acceptance Criteria

- [ ] Existing policies that only use `services` and string `domains` render unchanged
- [ ] New request-aware rules render into a predictable canonical structure consumed by the enforcer
- [ ] Layered policy inputs compose without duplicate or ambiguous host or rule behavior
- [ ] Invalid rich-rule configs fail fast with actionable errors

## Applicable Learnings

- Policy schema should nest by concern for extensibility, but `m14.1` should avoid a broad top-level schema migration
  unless it is necessary. The current shipped top-level `services` plus `domains` surface is already in use.
- Security-sensitive policy rendering should keep one merge path. `render-policy` inside the proxy remains the source
  of truth.
- User-owned policy files must stay outside the writable workspace and mounted read-only into the container.
- The current baked-default plus layered-override pattern is the right base model for security-sensitive policy files.
- Devcontainer-specific policy should remain an additive layer on the shared `.agent-sandbox` policy files, not become a
  separate policy system.
- Strong ownership boundaries are safer than rewriting arbitrary user-edited YAML. This task should normalize and merge
  policy inputs, not invent a new editing surface.

## Plan

### Files Involved

- `images/proxy/render-policy` - primary implementation surface for validation, normalization, and layered merging
- `images/proxy/addons/enforcer.py` - minimal loader changes only if the canonical rendered format requires them; full
  request-aware enforcement remains `m14.2`
- `docs/policy/schema.md` - canonical documentation for the user-facing policy format and merge semantics
- `internal/embeddata/templates/policy.yaml` - base single-file policy template comments and examples
- `internal/embeddata/templates/user.policy.yaml` - shared layered policy template comments and examples
- `internal/embeddata/templates/user.agent.policy.yaml` - agent-specific layered policy template comments and examples
- `internal/embeddata/templates/policy.devcontainer.yaml` - managed devcontainer policy template comments and examples
- `internal/scaffold/policy.go` - loosen policy typing only if the template or managed write path must tolerate richer
  schema nodes during this task
- `internal/scaffold/policy_test.go`
- `internal/scaffold/init_test.go`
- `internal/scaffold/sync_test.go`
- `internal/cli/policy_test.go` - verify `agentbox policy config` still exposes the rendered result cleanly
- New renderer-focused tests that exercise `images/proxy/render-policy` directly rather than only through CLI
  invocation

### Approach

The main trap in `m14.1` is treating "add object entries under `domains`" as a small schema tweak. It is not. The
current renderer assumes `domains` is a list of strings and merges it by simple union. As soon as `domains` can carry
objects, list position becomes ambiguous and layered merge behavior becomes underspecified. That ambiguity has to be
resolved here or every later task will inherit it.

The working approach is:

1. Keep the existing top-level `services` and `domains` fields for backward compatibility. Do not turn this task into a
   broader migration to a new top-level `egress:` shape.
2. Allow `domains` entries in authored YAML to be either:
   - a string, for the legacy host-only allowlist path
   - a mapping, for a host entry that also carries nested request rules
3. Normalize all authored inputs into a canonical rendered policy IR before enforcement. In that IR, every `domains`
   entry should be an object with a normalized `host` key plus an explicit rules collection, even when the authored
   input was a plain string.
4. Treat `services` as semantic authored shortcuts, not as another spelling of host records. The renderer should expand
   service declarations into the same canonical host-record IR as authored `domains` entries, so downstream enforcement
   sees one policy shape.
5. Service declarations are allowed to have service-specific authored schemas and options. They do not need to share the
   same input shape as rich `domains` records as long as they compile into the same rendered IR.
6. Existing simple services may still expand to catch-all host records, but richer service-specific option schemas such
   as GitHub repo scoping are deferred to `m14.3`.
7. Merge layers in existing order: service expansion or baseline first, then shared policy, then agent policy, then
   devcontainer policy.
8. Host records with the same normalized host identity should merge across layers rather than by list position. Within a
   host entry, default to additive rule merging with stable order and de-duplication for equivalent rules.
9. Host records with different identities should coexist across layers, even if more than one of them can match a given
   request.
10. Resolve overlapping host-pattern matches at request-evaluation time by specificity. Exact host records beat wildcard
   host records, and among wildcard host records the longest matching suffix wins.
11. User-authored host records should be able to override service-expanded host records or earlier-layer host records
   with the same normalized host identity through the same
   `merge_mode: replace` behavior used for layered policy inputs.
12. Add an authored-only escape hatch for host-level override via `merge_mode: replace`. The renderer should consume that
   directive during layering and strip it from the rendered output.
13. Include `schemes` as a rule dimension now rather than treating `http` and `https` as equivalent by omission.
14. Treat headers and request bodies as out of scope for `m14.1`. A matched URL rule currently means the endpoint is
   trusted to receive the full request; deeper inspection is future work.
15. Keep the policy model allow-only. Do not add `allow`/`deny` rule polarity or "allow everything on this host except
   these" semantics in `m14.1`.

That gives `m14.2` one policy shape to consume while still letting authored YAML stay readable and backward compatible.
It also confines the merge contract to something humans can reason about in code review: host entries are keyed by
host, and rules are accumulated deterministically.

Testing should target `render-policy` directly. Relying only on `agentbox policy config` would prove that the CLI can
invoke the helper, but it would not prove the policy merge semantics themselves. This is security-sensitive enough that
the renderer needs its own direct coverage for legacy, mixed, layered, and invalid inputs. The test direction is now
Python unit tests for proxy-image Python code, plus a GitHub workflow that runs them on merge paths.

### Proposed Policy Record Shape

This is the current proposal for review before renderer work begins.

#### Authored policy input

Legacy host-only authored input remains valid:

```yaml
services:
  - github

domains:
  - api.openai.com
  - "*.example.com"
```

Rich authored host entries use `host` as the canonical key:

```yaml
services:
  - github

domains:
  - api.openai.com

  - host: api.github.com
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          prefix: /repos/example/
        query:
          exact: {}

      - schemes: [https]
        path:
          exact: /meta
```

Layered authored input can replace the entire accumulated host record with an explicit merge directive:

```yaml
domains:
  - host: api.github.com
    merge_mode: replace
    rules:
      - scheme: https
        method: get
        path:
          prefix: /repos/my-org/
```

Notes:

- `merge_mode: replace` is an authoring directive, not part of the rendered IR
- absence of `merge_mode` means additive host merge with rule de-duplication when the same normalized host identity
  appears in multiple layers
- rendered policy should not retain symbolic `services`; they are compiled away into canonical host records
- service declarations are semantic shortcuts and may use service-specific option schemas
- service-specific authored schemas are deferred beyond `m14.1`; this task only fixes the rendered IR contract
- layers merge first, then host-pattern specificity is applied when evaluating a request
- overlapping host patterns are allowed, but only the most specific matching host record should participate at
  enforcement time
- exact host records outrank wildcard host records; among wildcards, the longest matching suffix wins
- `schemes` should live on rules, not on the host record, so match semantics stay in one place
- authored omission of `schemes` and `scheme` means both `http` and `https`
- authored `scheme` is a singular shorthand for `schemes`
- if both `scheme` and `schemes` are supplied, the renderer should warn on `stderr`, merge the values, normalize them,
  and de-duplicate them
- authored method names should be accepted case-insensitively and normalized to uppercase in the rendered policy
- authored omission of `methods` and `method` means any method
- authored `method` is a singular shorthand for `methods`
- if both `method` and `methods` are supplied, the renderer should warn on `stderr`, merge the values, normalize them
  to uppercase, and de-duplicate them
- rendered policy should prefer explicit catch-all rules over `rules: []`, so scheme intent remains expressible even for
  host-wide allows
- each rule should carry at most one path matcher; multiple allowed path alternatives should be written as multiple
  rules rather than one compound path list
- in examples and docs, list rule fields in request-matching order: `schemes`, `methods`, `path`, then `query`
- `path`, `schemes`, `methods`, and `query` are each optional individually
- a rule must not be empty after normalization; host-wide trust must be expressed explicitly, for example via
  `schemes: [https]` or an explicit catch-all rule emitted by the renderer
- the policy model is allow-only for `m14.1`; "all requests on this host except these" is intentionally out of scope
- for `m14.1`, the recommended query-record shape is an explicit query match mode rather than implicit per-param
  constraints, because "no query params" must be distinguishable from "I do not care about query params"

#### Proposed query record shape

The current recommendation is to keep the first query shape narrow and conservative:

```yaml
rules:
  - schemes: [https]
    methods: [GET]
    path:
      exact: /meta
    query:
      exact: {}
```

That expresses "GET request with no query params."

Specific query-param values can be expressed with the same exact-match form:

```yaml
rules:
  - schemes: [https]
    methods: [GET]
    path:
      exact: /meta
    query:
      exact:
        ref: docs
```

Notes:

- `query` omitted means query string is not constrained by that rule
- `query.exact: {}` means the request must have no query params
- authored `query.exact.<name>: value` should be accepted as shorthand for a single-item list
- `query.exact.<name>` uses a list of string values in the canonical rendered form so repeated params are representable
- exact query matching should ignore pair ordering and compare normalized per-key value lists
- the first version should prefer exact query matching over looser subset matching; it covers the current requirement
  without introducing ambiguity about extra params
- if we later need "must contain this param/value but may include extras," that should be an explicit future match mode,
  not an overloaded interpretation of `exact`

#### Rendered policy IR

Rendered policy should normalize all `domains` entries to the rich object form, even when authored input used legacy
strings. It should also normalize host-wide allows to an explicit catch-all rule rather than `rules: []`:

```yaml
domains:
  - host: api.openai.com
    rules:
      - schemes:
          - http
          - https

  - host: "*.example.com"
    rules:
      - schemes:
          - http
          - https

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
      - schemes:
          - https
        path:
          exact: /meta
```

The renderer should:

- preserve authored compatibility for string entries
- normalize host records into one rendered shape
- expand `services` into host records so downstream enforcement consumes one canonical IR
- treat service declarations as semantic inputs that compile into host records rather than as generic host-record syntax
- apply the existing layer order before request-matching precedence is considered
- preserve enough host-pattern information in the rendered policy for the matcher to resolve overlapping exact and
  wildcard records by specificity
- normalize rule records into one rendered shape with explicit `schemes`
- treat omitted authored `schemes` as `[http, https]` and always emit explicit rendered `schemes`
- treat omitted authored `methods` as wildcard-any and leave `methods` absent in the rendered policy unless the rule
  actually constrains methods
- normalize `scheme` plus `schemes` into one rendered `schemes` list and warn on `stderr` if both forms were supplied
- normalize `method` plus `methods` into one rendered uppercase `methods` list and warn on `stderr` if both forms were
  supplied
- normalize `query.exact` scalar values into single-item lists in the rendered policy
- reject empty authored rule objects rather than silently treating them as host-wide allow
- apply `merge_mode: replace` before output
- emit no merge-control directives in the rendered policy
- not add `allow`/`deny` polarity to rules in `m14.1`
- not add header or request-body match dimensions in `m14.1`

### Implementation Steps

- [ ] Lock the canonical authored shape and rendered IR shape with concrete examples before touching merge code
- [ ] Extend `images/proxy/render-policy` to validate, normalize, and merge mixed string and object `domains` entries
- [ ] Define deterministic cross-layer merge rules for same-identity host records, and implement rule append plus
      de-duplication without positional list semantics
- [ ] Define and test the layer-order model separately from host-pattern match precedence
- [ ] Define and test host-pattern precedence so overlapping exact and wildcard records resolve by specificity rather
      than broadening each other implicitly
- [ ] Add direct renderer tests for legacy string domains, mixed authored inputs, layered merges, invalid configs, and
      single-file versus layered rendering
- [ ] Add direct renderer tests proving that symbolic `services` compile into the same host-record IR as authored
      `domains` entries
- [ ] Defer service-specific authored option schemas such as repo-scoped GitHub declarations to `m14.3` while keeping
      the rendered IR stable
- [ ] Update `docs/policy/schema.md` and policy templates so the new format is documented without breaking the simple
      host-only path
- [ ] Make only the downstream compatibility changes needed for `m14.2` to consume the rendered IR cleanly
- [ ] Verify `agentbox policy config` still exposes the rendered policy and existing domain-only projects remain
      semantically unchanged

### Open Questions

- No current blocker in Go scaffolding: keep rich-schema work focused on user-owned policy files plus the proxy-side
  renderer unless managed policy generation later needs to emit or preserve rich rules during `m14`.

## Outcome

### Acceptance Verification

- Pending execution.

### Learnings

- None yet. Planning only.

### Follow-up Items

- Resolve the schema and merge-contract open questions before approving implementation.
