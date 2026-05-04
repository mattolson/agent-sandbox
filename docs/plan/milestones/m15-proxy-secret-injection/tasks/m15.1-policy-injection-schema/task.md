# Task: m15.1 - Policy Transform Schema

## Summary

Extend the policy renderer schema so explicit `domains` entries can author request header transforms as a peer to `host`
and `rules`.

## Scope

- Validate `domains[].transform.request.headers` with logical secret IDs matching `[A-Za-z0-9._-]+`, `basic` and
  `bearer` transforms, and `on_existing_header`
- Reserve `domains[].transform.response` and reject non-empty response transforms until response mutation is implemented
- Render request transforms as rule-scoped metadata so host-record merging cannot broaden a credential to unrelated rules
- Define the canonical transform metadata shape and validation helpers so later service catalog auth can emit the same
  representation
- Keep rendered output redacted and free of secret values
- Add the minimum matcher loader support needed for rendered policies containing transform metadata to load safely
- Exclude file-backed secret loading, secret resolution, and runtime request mutation
- Exclude service catalog auth shorthand, client compatibility shims, and user-facing docs; those belong to later m15
  tasks

## Acceptance Criteria

- [x] Renderer tests cover valid explicit request transform rules, invalid secret IDs, invalid transforms, invalid
      `on_existing_header` values, and non-empty response transform rejection
- [x] Merge tests prove transform metadata stays attached only to the rules emitted by the authored entry
- [x] `agentbox policy config` / rendered policy output contains secret IDs but no secret values
- [x] The proxy matcher can load rendered rule-scoped transform metadata without applying it yet
- [x] Existing policies without injection render and load unchanged

## Applicable Learnings

- Security-sensitive policy rendering should keep one merge path. `render-policy` inside the proxy remains the source of
  truth.
- A renderer-side service catalog that emits canonical host-record fragments keeps service semantics out of the matcher;
  this task should preserve the generic matcher boundary and avoid GitHub-specific behavior.
- Service-level `merge_mode: replace` works cleanly when rule ownership is tracked through rendering; transform metadata
  needs the same care so merge and dedupe do not widen credentials.
- Canonical catalog output should not be re-normalized inside the renderer; any transform IR emitted by the renderer
  should be canonical enough for downstream consumers.
- The initial-load path in `PolicyMatcher.from_policy_path` is stricter than the renderer, so matcher compatibility must
  be considered when the rendered IR changes.

## Plan

### Files Involved

- `images/proxy/render-policy` - primary schema validation, normalization, rule-scoped transform rendering, and merge
  behavior
- `images/proxy/policy_injection.py` - shared canonical transform metadata validation helpers for the renderer,
  matcher, and later service catalog auth
- `images/proxy/addons/policy_matcher.py` - minimal runtime data model/loader support for transform metadata, without
  request mutation
- `images/proxy/Dockerfile` - packaging for the shared transform helper used by both renderer and addon code
- `images/proxy/tests/test_render_policy.py` - renderer coverage for valid, invalid, and merge/dedupe cases
- `images/proxy/tests/test_policy_matcher.py` - matcher coverage proving rendered transform metadata loads without
  changing allow/block decisions

### Approach

Keep `m15.1` focused on the policy IR. The key behavior is that authored `domains[].transform.request` is a default for
the rules in that same authored entry, not a host-wide setting. During rendering, the request transform config should be
associated with each normalized rule from that entry before the host-record merge path runs.

The rendered rule shape should remain redacted and backend-neutral: it may include secret IDs and transform metadata,
but never resolved secret values. The renderer should normalize and validate this metadata, then strip any internal rule
owner tags exactly as it does today for normal rules.

The normalization should be factored so this PR owns the canonical transform metadata shape, while later catalog-auth
work can reuse the same representation without introducing GitHub branches in the matcher or duplicating validation.
Do not add service-auth authoring or client compatibility shim output in this PR.

The matcher currently rejects unknown rule keys, so this task also needs a narrow loader change. It should parse or
store the transform metadata on the runtime rule so later tasks can use it, but it must not inject headers or alter
allow/block decisions in this PR.

Validation should stay direct and low-level. Renderer tests should drive `render-policy` directly. Matcher tests should
prove compatibility with the new rendered shape, not runtime injection.

### Implementation Steps

- [x] Define the canonical rendered `transform.request` shape on individual rules
- [x] Add renderer normalization for `domains[].transform.request.headers`
- [x] Reserve and reject non-empty `domains[].transform.response`
- [x] Factor transform validation/normalization so later service catalog expansion can emit the same canonical shape
- [x] Add secret ID validation that accepts only `[A-Za-z0-9._-]+`
- [x] Add transform validation for `basic` and `bearer`
- [x] Add `on_existing_header` validation for `fail` and `replace`, defaulting to `fail`
- [x] Update host-record merge/dedupe identity so transform metadata remains rule-scoped and cannot broaden across
      unrelated same-host rules
- [x] Add matcher data model support for loading rule-scoped transform metadata without using it
- [x] Add renderer tests for valid output, invalid schema, redaction, and merge behavior
- [x] Add matcher tests proving transform metadata does not change request matching yet
- [x] Run the proxy Python test suite, or at minimum the renderer and matcher tests with `/opt/proxy-python/bin/python3`

### Open Questions

(None currently)

## Outcome

### Acceptance Verification

- [x] Renderer tests cover valid explicit request transform rules, invalid secret IDs, invalid transforms, invalid
      `on_existing_header` values, and non-empty response transform rejection.
- [x] Merge tests prove transform metadata stays attached only to the rules emitted by the authored entry.
- [x] Rendered policy output contains logical secret IDs and rejects raw secret-value fields in
      `transform.request.headers`.
- [x] The proxy matcher loads rendered rule-scoped transform metadata into runtime metadata without applying it yet.
- [x] Existing policies without injection render and load unchanged through the existing renderer and matcher regression
      suite.
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` passed.

### Learnings

- Shared proxy helper modules used by both `render-policy` and addons must account for the image layout. The renderer
  helpers live under `/usr/local/lib/agent-sandbox/proxy`, while addons run from `/home/mitmproxy/addons`.
- Keeping transform metadata on the rule before host-record merge lets the existing full-rule dedupe identity preserve
  credential scope without introducing a separate host-level injection merge path.

### Follow-up Items

- `m15.4` should revisit whether injected rules must force request inspection at CONNECT time once header mutation is
  implemented. `m15.1` deliberately leaves allow/block behavior unchanged.
