# Task: m14.3 - Semantic Service Catalog

## Summary

Replace the flat service-to-domain expansion model with a richer service catalog that can emit semantic rule bundles,
starting with GitHub restriction use cases.

## Scope

- Replace the inline `SERVICE_DOMAINS` mapping in `images/proxy/render-policy` with structured service definitions or
  compiled policy fragments
- Add repo-scoped GitHub restriction flows for both REST API access and Git smart-HTTP access, with `repos` list
  support, using the same matcher and rendered host-record IR as user-authored `domains` rules
- Preserve the current simple authoring path for services that still only need broad domain allowlists
- Add a generic service-level `readonly` boolean so services can request narrowed read-only expansion when needed, while
  `false` or omission defaults to readwrite behavior without introducing service-specific matcher behavior
- For the GitHub `git` surface, make `readonly` semantic enough to support clone and fetch by expanding to the
  smart-HTTP paths and methods those operations actually use
- Keep service definitions data-driven and reviewable rather than adding service-specific branches to the matcher
- Reuse the existing rendered-policy merge path so service expansions still participate in host-level merge, de-dupe,
  and specificity ordering exactly like authored domain entries
- Add explicit service-level `merge_mode: replace` semantics so a later rich service entry can replace earlier
  expansions for the same service name before host-level merging happens
- Document the richer `services` authoring surface and add focused examples without turning this task into the full
  migration-and-doc-lockdown work reserved for `m14.5`

## Acceptance Criteria

- [ ] Repo-scoped GitHub restriction scenarios can be expressed through `services` for both `api` and `git` surfaces,
      with one or more `repos`, without ad hoc proxy logic
- [ ] Existing baseline services still render to equivalent behavior when they only need host-wide domain access
- [ ] Service entries can be authored in a richer form without breaking existing plain-string `services` declarations
- [ ] Generic service-level `readonly: true` can narrow emitted rules at render time, with false or omission defaulting
      to readwrite behavior, while keeping the matcher unchanged
- [ ] The GitHub `git` surface maps `readonly: true` to clone or fetch-capable smart-HTTP rules, including
      `git-upload-pack`, while still excluding push-oriented `git-receive-pack`
- [ ] Invalid service-specific config fails rendering with actionable errors
- [ ] Service definitions are testable in isolation from the rest of `render-policy`
- [ ] The matcher and addon continue to consume only the canonical rendered host-record IR; no GitHub-specific matcher
      branches are introduced
- [ ] Same-name service entries are additive after expansion when `merge_mode` is omitted
- [ ] `merge_mode: replace` on a service entry discards prior expansions for that service name before the new service
      fragments enter host-record merging
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
- `docs/policy/examples/github-repos.yaml` - likely new focused example showing repo-scoped GitHub access through a
  `repos` list
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
    merge_mode: replace
    readonly: true
    repos:
      - owner/repo
      - owner/other-repo
    surfaces:
      - api
      - git
```

Working assumptions behind that shape:

- Plain string entries normalize to `{name: <service>}` internally and preserve today's broad service behavior.
- `name` selects the service definition in the catalog.
- `repos` is a required non-empty list of `owner/name` strings.
- A one-item `repos` list remains the common sandbox case, but supporting multiple repos adds only linear expansion and
  validation cost.
- `surfaces` keeps GitHub expansion explicit. `api` and `git` are both in scope for `m14.3`; add other surfaces only if
  they are needed and stay reviewable.
- `readonly` is a generic expansion hint, not a matcher feature.
- `readonly: false` and omitted `readonly` mean the same thing: preserve the service's normal emitted rules.
- `merge_mode: replace` is authoring-only, consumed during service expansion, and stripped before the rendered policy is
  finalized.
- GitHub service expansion should emit the same rule families for each listed repo; `repos` list order must not affect
  rendered behavior beyond stable deterministic output ordering.

#### Readonly Flag

The generic `readonly` flag should stay narrow:

- absent or `readonly: false` means "do not add extra method restrictions." It should preserve the service's normal
  emitted rules rather than trying to enumerate every writable verb.
- `readonly: true` means "narrow emitted rules to `GET` plus `HEAD`" at render time by default.

This should be applied to the service's emitted rule fragments before those fragments enter normal host-record merging.
The matcher already understands `methods`; it should not learn what `readonly` means.

For ordinary HTTP API surfaces, that literal mapping is enough. Git smart-HTTP is the exception that proves the rule:
clone and fetch still use `POST` to `git-upload-pack`, so a literal `GET` plus `HEAD` mapping would block Git
read-only workflows.

`m14.3` should handle that at service expansion time, not in the matcher. For the GitHub `git` surface:

- `readonly` should expand to the exact repo-scoped rules needed for clone and fetch
- `readwrite` should expand to the same read paths plus push-capable `git-receive-pack` rules
- the semantic mapping stays local to the GitHub service definition; it is not a new generic matcher concept

That keeps the authored flag generic while admitting the real protocol behavior. The renderer owns the semantic
translation from "`readonly: true` on GitHub smart-HTTP" into ordinary host, path, query, and method rules.

For the first GitHub restriction flow, `m14.3` should cover both repo-scoped REST access on `api.github.com` and
repo-scoped Git smart-HTTP on `github.com` for every entry in the authored `repos` list.

The `api` surface should cover rules such as:

- exact `/repos/{owner}/{repo}`
- prefix `/repos/{owner}/{repo}/`

The `git` surface should cover the canonical single-repo smart-HTTP paths on `github.com`, including:

- exact `/{owner}/{repo}.git`
- exact `/{owner}/{repo}.git/info/refs` with service query matching for `git-upload-pack` and `git-receive-pack`
- exact `/{owner}/{repo}.git/git-upload-pack`
- exact `/{owner}/{repo}.git/git-receive-pack`

For GitHub `git`, the intended `readonly` mapping is:

- `readonly: true`: allow `GET` or `HEAD` to `info/refs?service=git-upload-pack` and allow `POST` to
  `/{owner}/{repo}.git/git-upload-pack`
- omitted `readonly` or `readonly: false`: allow the `readonly: true` set plus the matching `git-receive-pack`
  discovery and POST endpoints used for push

That keeps clone and fetch working under `readonly: true` while still excluding push.

That is enough to keep repo-scoped Git transport visible in the URL path and to support later credential work without
quietly broadening the host allowlist. `m15` remains about the higher-level REST wrapper surface; adding Git smart-HTTP
to `m14.3` does not replace that milestone.

#### Merge And Override Semantics

The service-level merge model should now be explicit:

- Same-name service entries are additive by default when `merge_mode` is omitted.
- "Additive" means each service entry expands independently into host-rule fragments, and those fragments then flow
  through normal host-record merging.
- Service option mappings are **not** merged field by field. The renderer must not synthesize one combined service
  config from multiple authored entries.
- `merge_mode: replace` on a service entry discards prior expansions for that service `name`, then applies the new
  service entry's expanded fragments.
- After service expansion is complete, emitted host records still participate in the existing host-level merge behavior,
  including authored `domains` entries with host-level `merge_mode: replace`.

This avoids the dangerous middle ground where users assume two service configs with the same name will be structurally
merged or that a later narrower config will implicitly override an earlier broader one. It will not. Narrowing requires
either service-level `merge_mode: replace` or authored host-level replacement under `domains`.

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

- [ ] Decide and document the normalized authored shape for richer service entries, including the `readonly` boolean and
      service-level `merge_mode: replace`
- [ ] Extract the flat `SERVICE_DOMAINS` map into a dedicated renderer-side service catalog boundary
- [ ] Keep simple services data-only and equivalent to current host-wide behavior
- [ ] Implement generic `readonly` handling at render time, with false or omission preserving existing behavior and
      `readonly: true` narrowing emitted rules to `GET` plus `HEAD`
- [ ] Implement GitHub `git` readonly semantics at render time so `readonly: true` emits clone or fetch-capable
      `git-upload-pack` rules and omitted or false `readonly` adds push-capable `git-receive-pack` rules
- [ ] Implement the first GitHub repo-scoped service expansion around a `repos` list and explicit `api` plus `git`
      surfaces that keep repo identity visible in request URLs
- [ ] Validate and test multi-repo list expansion so each listed repo emits deterministic rule fragments without
      changing merge semantics
- [ ] Make same-name service entries additive after expansion by default and implement `merge_mode: replace` by service
      name
- [ ] Route service expansion output through the existing host-record normalization and merge path instead of creating a
      second policy pipeline
- [ ] Add direct unit tests for service validation and expansion behavior
- [ ] Add renderer integration tests for backward compatibility and GitHub-specific rendered output
- [ ] Add one runtime integration test proving the generated fragments enforce correctly through the generic matcher
- [ ] Update schema docs, templates, and at least one focused example policy

### Open Questions

- Does the catalog live as Python data structures only, or is there enough value in a declarative data file to justify
  the extra loader surface now?
- How much authored schema should be documented in `m14.3` versus deferred to the broader lock-down pass in `m14.5`?
- Do we later need a more formal abstraction than a boolean `readonly` flag for protocol-shaped services, or is
  per-service semantic expansion at render time enough for the foreseeable surfaces?

## Outcome

### Acceptance Verification

Pending execution.

### Learnings

Pending execution.

### Follow-up Items

Pending execution.
