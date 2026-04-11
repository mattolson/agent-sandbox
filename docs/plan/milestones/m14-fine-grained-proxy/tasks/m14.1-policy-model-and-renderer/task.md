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

The recommended approach is:

1. Keep the existing top-level `services` and `domains` fields for backward compatibility. Do not turn this task into a
   broader migration to a new top-level `egress:` shape.
2. Allow `domains` entries in authored YAML to be either:
   - a string, for the legacy host-only allowlist path
   - a mapping, for a host entry that also carries nested request rules
3. Normalize all authored inputs into a canonical rendered policy IR before enforcement. In that IR, every `domains`
   entry should be an object with a normalized host key plus an explicit rules collection, even when the authored input
   was a plain string.
4. Keep `services` symbolic in the rendered policy for now. Expanding them into richer semantic bundles belongs to
   `m14.3`; this task should not solve that problem early.
5. Merge rich domain entries by normalized host identity, not by list position. Within a host entry, prefer append with
   stable order and de-duplication for equivalent rules over positional deep-merge of rule arrays.

That gives `m14.2` one policy shape to consume while still letting authored YAML stay readable and backward compatible.
It also confines the merge contract to something humans can reason about in code review: host entries are keyed by
host, and rules are accumulated deterministically.

Testing should target `render-policy` directly. Relying only on `agentbox policy config` would prove that the CLI can
invoke the helper, but it would not prove the policy merge semantics themselves. This is security-sensitive enough that
the renderer needs its own direct coverage for legacy, mixed, layered, and invalid inputs.

### Implementation Steps

- [ ] Lock the canonical authored shape and rendered IR shape with concrete examples before touching merge code
- [ ] Extend `images/proxy/render-policy` to validate, normalize, and merge mixed string and object `domains` entries
- [ ] Define deterministic host-entry merge rules for layered policy files and implement rule append plus de-duplication
      without positional list semantics
- [ ] Add direct renderer tests for legacy string domains, mixed authored inputs, layered merges, invalid configs, and
      single-file versus layered rendering
- [ ] Update `docs/policy/schema.md` and policy templates so the new format is documented without breaking the simple
      host-only path
- [ ] Make only the downstream compatibility changes needed for `m14.2` to consume the rendered IR cleanly
- [ ] Verify `agentbox policy config` still exposes the rendered policy and existing domain-only projects remain
      semantically unchanged

### Open Questions

- Should the rich host entry use `domain:` or `host:` as its canonical key? The current code and docs say "domain," but
  request matching is hostname-based and `host` may be clearer.
- Should the rendered policy preserve mixed string or object input forms, or always normalize to an object-only IR?
  The stronger recommendation is object-only IR.
- Do we want rule lists to append with de-duplication across layers, or should later layers replace the entire rule set
  for a host? Append plus de-duplication is more consistent with the current union semantics, but it should be chosen
  explicitly.
- Does `internal/scaffold/policy.go` need to become more schema-tolerant in `m14.1`, or can that wait because current
  scaffold paths mostly write empty default policy files and do not round-trip user-edited rich entries?
- What is the lightest-weight direct test harness for `render-policy` that the repo will maintain comfortably: a small
  Go subprocess test, or a Python-native unit test module?

## Outcome

### Acceptance Verification

- Pending execution.

### Learnings

- None yet. Planning only.

### Follow-up Items

- Resolve the schema and merge-contract open questions before approving implementation.
