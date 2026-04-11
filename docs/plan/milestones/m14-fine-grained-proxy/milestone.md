# Milestone: m14 - Fine-Grained Proxy Rules

## Goal

Extend proxy enforcement from host-only allowlists to request-aware policy rules for HTTP and HTTPS, without weakening
the current default-deny model or the layered policy ownership model. `m14` should make path, method, and
query-parameter filtering available to later milestones while keeping existing domain-only policies working unchanged
and preserving CONNECT-time blocking as a fast path when full request inspection is unnecessary.

## Scope

**Included:**
- Request-aware matching for HTTP and HTTPS based on host, path, method, and query parameters
- Backward-compatible domain-only behavior, including CONNECT-time fast-path blocking for host-only rules
- Policy schema and `render-policy` changes needed to express and merge nested request rules under domain entries
- Rich service definitions that can expand to semantic rule bundles, starting with GitHub restriction use cases
- SIGHUP-driven policy hot reload with atomic validation and last-good fallback
- Structured logging, docs, examples, and automated coverage for the new behavior

**Excluded:**
- Secret injection, header substitution, or other credential features from `m15`
- Monitoring UI or interactive unblock workflows from `m16`
- Non-HTTP protocols
- Request or response body mutation, response shaping, or full content filtering
- A separate host-side policy renderer or a new policy ownership model

## Applicable Learnings

- Policy schema should nest by concern for extensibility. `m14` should evolve the existing policy format rather than
  bolt request rules into one-off fields.
- Security-sensitive policy rendering should keep one merge path. `render-policy` inside the proxy remains the source
  of truth.
- User-owned policy files must stay outside the writable workspace and mounted read-only into the container.
- The current "baked default + optional layered override" pattern fits security-sensitive config and should remain
  intact.
- `iptables` as gatekeeper plus proxy as enforcer remains the core model. `m14` adds expressiveness at the proxy, not a
  second enforcement layer.

## Tasks

### m14.1-policy-model-and-renderer

**Summary:** Define and implement a canonical request-aware policy model that supports deterministic layered merges
without breaking existing `services` plus string `domains` policies.

**Scope:**
- Decide the canonical YAML shape for rich domain entries and nested request rules
- Extend `images/proxy/render-policy` validation and normalization to accept both legacy string domains and new
  rule-bearing entries
- Preserve the current layered policy inputs and single render path inside the proxy
- Define deterministic merge identity for rich domain entries across shared, agent-specific, and devcontainer layers
- Update schema docs and examples so the new format is reviewable and not guesswork

**Acceptance Criteria:**
- Existing policies that only use `services` and string `domains` render unchanged
- New request-aware rules render into a predictable canonical structure consumed by the enforcer
- Layered policy inputs compose without duplicate or ambiguous host or rule behavior
- Invalid rich-rule configs fail fast with actionable errors

**Dependencies:** None

**Risks:** Rich rule objects inside `domains` create ambiguous merge behavior unless each entry has a stable identity.
Do not rely on list position as the merge key.

### m14.2-request-phase-enforcement

**Summary:** Move enforcement to a matcher that can inspect decrypted HTTPS requests and apply method, path, and query
rules while preserving the existing host-only CONNECT fast path.

**Scope:**
- Implement shared request matching for HTTP and MITM'd HTTPS traffic
- Keep CONNECT-time blocking for policies that only need hostname checks
- Define path and query matching semantics tightly enough to be testable and reviewable
- Add structured allow and block logs that include request details and the reason a rule matched or failed
- Ensure HTTP and HTTPS share one policy evaluation path once the request is available

**Acceptance Criteria:**
- Host-only rules still block at CONNECT when possible
- HTTPS requests for rule-bearing hosts are allowed or blocked at request time based on method, path, and query rules
- HTTP and HTTPS matching semantics are aligned for the same policy
- Block logs carry enough detail to diagnose why a request failed without opening packet traces

**Dependencies:** m14.1

**Risks:** Query matching becomes brittle quickly if encoding, ordering, and repeated-key semantics are underspecified.
Keep the first version narrow and canonicalize before matching.

### m14.3-semantic-service-catalog

**Summary:** Replace the flat service-to-domain expansion model with a richer service catalog that can emit semantic
rule bundles, starting with GitHub restriction use cases.

**Scope:**
- Refactor `SERVICE_DOMAINS` into structured service definitions or compiled policy fragments
- Add at least one GitHub-focused restriction flow that uses the same matcher as user-authored rules
- Preserve the current simple authoring path for services that still only need domain allowlists
- Keep service definitions data-driven and auditable rather than hard-coding per-service branches in the matcher

**Acceptance Criteria:**
- At least one meaningful GitHub restriction scenario can be expressed without ad hoc proxy logic
- Existing agent baseline services still expand to equivalent behavior when they only need domain-level access
- Service definitions remain understandable in code review and testable in isolation

**Dependencies:** m14.1, m14.2

**Risks:** Hard-coding too much GitHub-specific logic into the enforcer would make later services awkward. The matcher
should stay generic, with service semantics expressed as data.

### m14.4-hot-reload-and-runtime-integration

**Summary:** Allow policy edits to take effect in a running proxy via `SIGHUP` without dropping healthy connections or
introducing a second policy render path.

**Scope:**
- Add reload handling in the proxy runtime and enforcer
- Re-render and validate policy on signal before swapping matcher state
- Keep the last known-good policy active if reload fails
- Emit structured reload success and failure logs
- Document the human and future-CLI workflow for validating and reloading policy changes

**Acceptance Criteria:**
- Sending `SIGHUP` to the proxy reloads policy without a container restart
- Existing healthy connections are not dropped solely because a reload happened
- Invalid reloaded policy is rejected atomically and leaves the prior policy active
- Reload still uses the proxy-side `render-policy` path rather than inventing a second merge implementation

**Dependencies:** m14.1, m14.2

**Risks:** mitmproxy signal and addon lifecycle behavior may not support safe in-place mutation directly. If that proves
false, use a small supervisor or explicit reload wrapper rather than claiming "hot reload" while really doing a
restart.

### m14.5-validation-docs-and-migration

**Summary:** Lock down the new behavior with automated coverage, migration guidance, and examples so later milestones
build on a stable policy surface.

**Scope:**
- Add tests for legacy domain-only fast path, request-aware allow and deny cases, service expansions, and hot reload
- Update `docs/policy/schema.md`, examples, and troubleshooting guidance for the richer rule model
- Document how domain-only behavior differs from request-phase behavior and when each applies
- Verify current agent images and template-generated baseline policies still work unchanged

**Acceptance Criteria:**
- Automated coverage exists for representative HTTP and HTTPS cases, including reload failure handling
- Docs show both legacy domain-only and new request-aware examples
- Users can tell whether a rule is enforced at CONNECT or request phase without reading proxy source
- Existing projects with domain-only policies continue to work unchanged

**Dependencies:** m14.1, m14.2, m14.3, m14.4

**Risks:** If every case is only tested end to end, the suite will be slow and fragile. Keep matcher logic unit-testable
and use a smaller set of proxy integration tests for wiring.

## Execution Order

1. **m14.1** first. The milestone will fail if rich rules are added before merge semantics and canonical rendering are
   defined.
2. **m14.2** next. Once the policy model is stable, move enforcement to a request-aware matcher while preserving the
   CONNECT fast path.
3. **m14.3** and **m14.4** can proceed in parallel after the matcher and policy IR settle. One extends the service
   catalog; the other wires live reload around the same rendered policy path.
4. **m14.5** last. Finish with automated coverage, migration docs, and examples once the behavior is stable enough to
   document precisely.

Critical path: `m14.1 -> m14.2 -> (m14.3, m14.4) -> m14.5`.

## Risks

- **Schema and merge ambiguity across layered policy files:** The current merge rules were designed for string lists.
  Rich host entries need stable identity or overlays will become surprising.
- **Behavioral regressions in the current domain-only path:** Moving enforcement later in the request lifecycle could
  accidentally weaken the existing simple allowlist model if CONNECT fast-path behavior regresses.
- **Overly expressive matching in v1:** Path and query filters can spiral into a mini policy language. Keep the first
  version narrow, explicit, and testable.
- **Hot reload safety:** Reload must be atomic. Partial matcher updates or silent fallback to allow-all semantics would
  be unacceptable.
- **Service catalog drift into one-off product logic:** GitHub is a useful proving ground, but the service model must
  remain reusable for other providers and later milestones.

## Definition of Done

- Existing domain-only policies still work unchanged, and host-only denies still happen at CONNECT when possible
- Policy rules can constrain HTTP and HTTPS requests by method, path, and query parameters
- The rendered policy format and merge behavior are documented, deterministic, and validated
- Service definitions can express at least one GitHub restriction use case through the generic matcher
- Sending `SIGHUP` reloads policy in place with last-known-good fallback on failure
- Proxy logs and automated tests cover representative legacy and request-aware allow and deny paths
- Documentation explains the new schema, migration path, and what remains out of scope for later milestones

## Changes

### 2026-04-10: Initial milestone plan

Created the first task breakdown for request-aware policy rules, semantic service expansions, and hot reload.
