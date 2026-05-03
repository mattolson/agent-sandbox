# Task: m15.1 - Policy Injection Schema

## Summary

Extend the policy renderer schema so explicit `domains` entries can author `inject` as a peer to `host` and `rules`.

## Scope

- Validate `domains[].inject.headers` with logical secret IDs matching `[A-Za-z0-9._-]+`, `basic` and `bearer`
  transforms, and `on_existing_header`
- Render injection as rule-scoped metadata so host-record merging cannot broaden an injected credential to unrelated
  rules
- Keep rendered output redacted and free of secret values
- Add the minimum matcher loader support needed for rendered policies containing injection metadata to load safely
- Exclude file-backed secret loading, secret resolution, and runtime request mutation
- Exclude service catalog auth shorthand, client compatibility shims, and user-facing docs; those belong to later m15
  tasks

## Acceptance Criteria

- [ ] Renderer tests cover valid explicit injection rules, invalid secret IDs, invalid transforms, and invalid
      `on_existing_header` values
- [ ] Merge tests prove injected metadata stays attached only to the rules emitted by the authored entry
- [ ] `agentbox policy config` / rendered policy output contains secret IDs but no secret values
- [ ] The proxy matcher can load rendered rule-scoped injection metadata without applying it yet
- [ ] Existing policies without injection render and load unchanged

## Applicable Learnings

- Security-sensitive policy rendering should keep one merge path. `render-policy` inside the proxy remains the source of
  truth.
- A renderer-side service catalog that emits canonical host-record fragments keeps service semantics out of the matcher;
  this task should preserve the generic matcher boundary and avoid GitHub-specific behavior.
- Service-level `merge_mode: replace` works cleanly when rule ownership is tracked through rendering; injection metadata
  needs the same care so merge and dedupe do not widen credentials.
- Canonical catalog output should not be re-normalized inside the renderer; any injection IR emitted by the renderer
  should be canonical enough for downstream consumers.
- The initial-load path in `PolicyMatcher.from_policy_path` is stricter than the renderer, so matcher compatibility must
  be considered when the rendered IR changes.

## Plan

### Files Involved

- `images/proxy/render-policy` - primary schema validation, normalization, rule-scoped injection rendering, and merge
  behavior
- `images/proxy/addons/policy_matcher.py` - minimal runtime data model/loader support for injection metadata, without
  request mutation
- `images/proxy/tests/test_render_policy.py` - renderer coverage for valid, invalid, and merge/dedupe cases
- `images/proxy/tests/test_policy_matcher.py` - matcher coverage proving rendered injection metadata loads without
  changing allow/block decisions

### Approach

Keep `m15.1` focused on the policy IR. The key behavior is that authored `domains[].inject` is a default for the rules
in that same authored entry, not a host-wide setting. During rendering, the injection config should be copied or
associated with each normalized rule from that entry before the host-record merge path runs.

The rendered rule shape should remain redacted and backend-neutral: it may include secret IDs and transform metadata,
but never resolved secret values. The renderer should normalize and validate this metadata, then strip any internal rule
owner tags exactly as it does today for normal rules.

The matcher currently rejects unknown rule keys, so this task also needs a narrow loader change. It should parse or
store the injection metadata on the runtime rule so later tasks can use it, but it must not inject headers or alter
allow/block decisions in this PR.

Validation should stay direct and low-level. Renderer tests should drive `render-policy` directly. Matcher tests should
prove compatibility with the new rendered shape, not runtime injection.

### Implementation Steps

- [ ] Define the canonical rendered `inject` shape on individual rules
- [ ] Add renderer normalization for `domains[].inject.headers`
- [ ] Add secret ID validation that accepts only `[A-Za-z0-9._-]+`
- [ ] Add transform validation for `basic` and `bearer`
- [ ] Add `on_existing_header` validation for `fail` and `replace`, defaulting to `fail`
- [ ] Update host-record merge/dedupe identity so injection metadata remains rule-scoped and cannot broaden across
      unrelated same-host rules
- [ ] Add matcher data model support for loading rule-scoped injection metadata without using it
- [ ] Add renderer tests for valid output, invalid schema, redaction, and merge behavior
- [ ] Add matcher tests proving injection metadata does not change request matching yet
- [ ] Run the proxy Python test suite, or at minimum the renderer and matcher tests with `/opt/proxy-python/bin/python3`

### Open Questions

(None currently)

## Outcome

### Acceptance Verification

Pending implementation.

### Learnings

Pending implementation.

### Follow-up Items

Pending implementation.
