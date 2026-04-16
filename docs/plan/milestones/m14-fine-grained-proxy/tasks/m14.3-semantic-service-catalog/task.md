# Task: m14.3 - Semantic Service Catalog

## Summary

Replace the flat service-to-domain expansion model with a richer service catalog that can emit semantic rule bundles,
starting with GitHub restriction use cases.

## Scope

- Replace the inline `SERVICE_DOMAINS` mapping in `images/proxy/render-policy` with structured service definitions or
  compiled policy fragments
- Add at least one GitHub-focused restriction flow that uses the same matcher and rendered host-record IR as
  user-authored `domains` rules
- Preserve the current simple authoring path for services that still only need broad domain allowlists
- Keep service definitions data-driven and reviewable rather than adding service-specific branches to the matcher
- Reuse the existing rendered-policy merge path so service expansions still participate in host-level merge, de-dupe,
  and specificity ordering exactly like authored domain entries
- Document the richer `services` authoring surface and add focused examples without turning this task into the full
  migration-and-doc-lockdown work reserved for `m14.5`

## Acceptance Criteria

- [ ] At least one meaningful GitHub restriction scenario can be expressed through `services` without ad hoc proxy logic
- [ ] Existing baseline services still render to equivalent behavior when they only need host-wide domain access
- [ ] Service entries can be authored in a richer form without breaking existing plain-string `services` declarations
- [ ] Invalid service-specific config fails rendering with actionable errors
- [ ] Service definitions are testable in isolation from the rest of `render-policy`
- [ ] The matcher and addon continue to consume only the canonical rendered host-record IR; no GitHub-specific matcher
      branches are introduced
- [ ] Docs and examples make the new authored service shape understandable in code review

## Applicable Learnings

- Security-sensitive policy rendering should keep one merge path. `render-policy` inside the proxy remains the source of
  truth.
- `m14.2` already established a clean runtime boundary: the matcher should stay generic and operate only on canonical
  host records plus rules.
- Policy schema should evolve by concern, but backward compatibility matters. The current top-level `services` field is
  already in use and should stay readable.
- For `m14`, a matched URL rule implies trust in the full request. Rich service definitions should still compile to URL
  shape constraints only, not drift into header or body semantics.
- Documentation artifacts belong in `docs/`, and managed templates should keep the simple path obvious even if richer
  service entries become available in user-owned policy files.

## Plan

### Files Involved

- `images/proxy/render-policy` - stop inlining the flat service map, parse richer service entries, and feed expanded
  service fragments through the existing host-record normalization and merge path
- `images/proxy/service_catalog.py` - new renderer-side catalog module that owns service-entry validation and expansion
  to canonical host-record fragments
- `images/proxy/tests/test_service_catalog.py` - new direct unit coverage for service entry normalization, GitHub
  restriction expansion, and invalid config handling
- `images/proxy/tests/test_render_policy.py` - renderer integration coverage proving plain-string services still render
  unchanged and richer services compile into the expected host records
- `images/proxy/tests/test_policy_matcher.py` or `images/proxy/tests/test_enforcer.py` - one integration proof that
  emitted GitHub-specific fragments enforce correctly through the generic matcher path
- `docs/policy/schema.md` - document the richer `services` entry form and its first GitHub example
- `docs/policy/examples/github-single-repo.yaml` - likely new focused example showing repo-scoped GitHub access
- `internal/embeddata/templates/policy.yaml`
- `internal/embeddata/templates/user.policy.yaml`
- `internal/embeddata/templates/user.agent.policy.yaml`

### Approach

The current `SERVICE_DOMAINS` map is too shallow for `m14.3`. It can only emit host-wide trust, which is exactly the
thing the milestone is trying to move past for GitHub. The wrong response would be to keep service expansion shallow and
then bolt GitHub-specific logic into `policy_matcher.py`. That would split policy semantics across render time and
request time, and it would make every future service harder to reason about.

The cleaner boundary is:

1. Keep `services` as the authored shortcut surface.
2. Let service entries be either:
   - a plain string, preserving the current behavior
   - a mapping with a required `name` plus service-specific options
3. Move service knowledge into a dedicated renderer-side catalog module.
4. Have the catalog expand each service entry into the same canonical host-record fragments that authored `domains`
   produce.
5. Feed those fragments back through the existing host-record normalization and merge pipeline.

That preserves the most important `m14.1` and `m14.2` contract: one rendered policy IR, one matcher model, one
precedence story.

#### Proposed Service Entry Shape

The first richer authored shape should stay narrow:

```yaml
services:
  - github

  - name: github
    repos:
      - owner/repo
    surfaces:
      - api
```

Working assumptions behind that shape:

- Plain string entries normalize to `{name: <service>}` internally.
- `name` selects the service definition in the catalog.
- `repos` gives the service enough structured input to emit repo-scoped rules.
- `surfaces` keeps GitHub expansion explicit. Start with `api` and add other surfaces only if they are needed and stay
  reviewable.

For the first GitHub restriction flow, the safest starting point is repo-scoped REST access on `api.github.com`, for
example rules covering:

- exact `/repos/{owner}/{repo}`
- prefix `/repos/{owner}/{repo}/`

That is already enough to unblock `m15`-style REST-only workflows without widening this task into "support every
GitHub endpoint family." If execution shows that Git smart-HTTP paths on `github.com` are also needed now, they should
be added as an explicit `git` surface rather than hidden inside the default `github` shortcut.

#### Merge And Override Semantics

There is one assumption here that needs to stay explicit: additive host-record merging does **not** magically narrow an
earlier broad service declaration. If a shared layer contains broad `services: [github]` and a later layer adds a
repo-scoped GitHub entry, the broad catch-all host records would still allow more than intended unless we add an
explicit replacement mechanism.

That means `m14.3` must choose one of these paths deliberately:

- add explicit service-entry replacement semantics that are reviewable and testable, or
- document that scoped service entries are additive shortcuts, not subtractive overlays, and users must remove broader
  service declarations when narrowing access

Pretending additive expansion narrows policy would be a design bug. Resolve this before implementation starts.

#### Catalog Representation

Keep the catalog data-driven, but do not force every service into the same oversimplified shape. A practical split is:

- simple services: static host patterns that expand to catch-all host records
- rich services: definitions with a validator plus an expander that emits canonical host-record fragments from
  structured options

The renderer should not construct matcher objects directly. It should keep emitting rendered YAML in the same canonical
IR that `policy_matcher.py` already knows how to load.

#### Test Strategy

Split tests by responsibility:

- `test_service_catalog.py` for entry normalization, option validation, GitHub fragment generation, and explicit error
  cases
- `test_render_policy.py` for layered renderer integration and backward-compatibility with plain-string services
- one matcher or enforcer integration test proving the generated GitHub fragments actually enforce through the generic
  runtime without service-specific branches

The direct catalog tests matter. If all validation lives only in `test_render_policy.py`, the catalog will drift back
into a hidden helper inside the renderer script.

### Implementation Steps

- [ ] Decide and document the normalized authored shape for richer service entries, including whether service-level
      replacement semantics are part of `m14.3`
- [ ] Extract the flat `SERVICE_DOMAINS` map into a dedicated renderer-side service catalog boundary
- [ ] Keep simple services data-only and equivalent to current host-wide behavior
- [ ] Implement the first GitHub repo-scoped service expansion, starting with a narrow surface set that keeps repo
      identity visible in request URLs
- [ ] Route service expansion output through the existing host-record normalization and merge path instead of creating a
      second policy pipeline
- [ ] Add direct unit tests for service validation and expansion behavior
- [ ] Add renderer integration tests for backward compatibility and GitHub-specific rendered output
- [ ] Add one runtime integration test proving the generated fragments enforce correctly through the generic matcher
- [ ] Update schema docs, templates, and at least one focused example policy

### Open Questions

- Should richer service entries support `merge_mode: replace` or a similar explicit narrowing mechanism, or is that
  better left to authored `domains` plus documentation in the first cut?
- Is the first meaningful GitHub scenario `api` only, or do we also need `git` smart-HTTP fragments in this task to
  avoid immediate follow-up churn?
- Should `repos` accept exactly one `owner/name` string at first, or a list from day one?
- Does the catalog live as Python data structures only, or is there enough value in a declarative data file to justify
  the extra loader surface now?
- How much authored schema should be documented in `m14.3` versus deferred to the broader lock-down pass in `m14.5`?

## Outcome

### Acceptance Verification

Pending execution.

### Learnings

Pending execution.

### Follow-up Items

Pending execution.
