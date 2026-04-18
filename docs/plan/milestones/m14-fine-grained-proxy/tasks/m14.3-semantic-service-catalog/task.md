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

- [x] Repo-scoped GitHub restriction scenarios can be expressed through `services` for both `api` and `git` surfaces,
      with one or more `repos`, without ad hoc proxy logic
- [x] Existing baseline services still render to equivalent behavior when they only need host-wide domain access
- [x] Service entries can be authored in a richer form without breaking existing plain-string `services` declarations
- [x] Generic service-level `readonly: true` can narrow emitted rules at render time, with false or omission defaulting
      to readwrite behavior, while keeping the matcher unchanged
- [x] The GitHub `git` surface maps `readonly: true` to clone or fetch-capable smart-HTTP rules, including
      `git-upload-pack`, while still excluding push-oriented `git-receive-pack`
- [x] Invalid service-specific config fails rendering with actionable errors
- [x] Service definitions are testable in isolation from the rest of `render-policy`
- [x] The matcher and addon continue to consume only the canonical rendered host-record IR; no GitHub-specific matcher
      branches are introduced
- [x] Same-name service entries are additive after expansion when `merge_mode` is omitted
- [x] `merge_mode: replace` on a service entry discards prior expansions for that service name before the new service
      fragments enter host-record merging
- [x] Docs and examples make the new authored service shape understandable in code review

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

Keep the catalog as Python-backed renderer logic for `m14.3`. Do not add a separate declarative catalog file yet. The
hard part of this task is still service-specific validation and expansion logic, so introducing a second schema now
would add loader and validation complexity without removing the real implementation work.

A practical split inside the Python catalog is:

- simple services: static host patterns that expand to catch-all host records
- rich services: definitions with a validator plus an expander that emits canonical host-record fragments from
  structured options

The renderer should not construct matcher objects directly. It should keep emitting rendered YAML in the same canonical
IR that `policy_matcher.py` already knows how to load.

Revisit a declarative catalog only if later rich services start duplicating the same expansion patterns enough to make
the Python-backed structure awkward.

#### Documentation Boundary

`m14.3` should document the authored surface that users must rely on to write policy safely:

- rich `services` entry shape
- `name`
- `repos`
- `surfaces`
- `readonly`
- service-level `merge_mode: replace`
- additive versus replace semantics
- the GitHub `git` readonly exception
- at least one focused example policy

What stays out of `m14.3` and belongs in `m14.5`:

- broader migration guidance
- final docs polish and troubleshooting coverage
- lock-down of the complete example set once behavior has stopped moving

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

- [x] Decide and document the normalized authored shape for richer service entries, including the `readonly` boolean and
      service-level `merge_mode: replace`
- [x] Extract the flat `SERVICE_DOMAINS` map into a dedicated renderer-side service catalog boundary
- [x] Keep simple services data-only and equivalent to current host-wide behavior
- [x] Implement generic `readonly` handling at render time, with false or omission preserving existing behavior and
      `readonly: true` narrowing emitted rules to `GET` plus `HEAD`
- [x] Implement GitHub `git` readonly semantics at render time so `readonly: true` emits clone or fetch-capable
      `git-upload-pack` rules and omitted or false `readonly` adds push-capable `git-receive-pack` rules
- [x] Implement the first GitHub repo-scoped service expansion around a `repos` list and explicit `api` plus `git`
      surfaces that keep repo identity visible in request URLs
- [x] Validate and test multi-repo list expansion so each listed repo emits deterministic rule fragments without
      changing merge semantics
- [x] Make same-name service entries additive after expansion by default and implement `merge_mode: replace` by service
      name
- [x] Route service expansion output through the existing host-record normalization and merge path instead of creating a
      second policy pipeline
- [x] Add direct unit tests for service validation and expansion behavior
- [x] Add renderer integration tests for backward compatibility and GitHub-specific rendered output
- [x] Add one runtime integration test proving the generated fragments enforce correctly through the generic matcher
- [x] Update schema docs, templates, and at least one focused example policy

### Open Questions

None for the planned `m14.3` slice.

Revisit only if additional rich services show that the Python-backed catalog or the boolean `readonly` model is no
longer a clean fit.

## Outcome

### Acceptance Verification

- [x] Repo-scoped GitHub restriction renders for both `api` and `git` surfaces with multi-repo support
      (`ServiceCatalogExpansionTests` covers `api`-only, `git`-only, combined surfaces, readonly plus readwrite, and
      deterministic multi-repo expansion; `test_rich_github_repo_scoped_service_renders_to_repo_paths` confirms the
      renderer emits the expected `api.github.com` and `github.com` host records end-to-end)
- [x] Plain-string services still render to equivalent baseline hosts
      (existing `test_render_policy.py` cases remained green; the legacy `SIMPLE_SERVICE_HOSTS` table preserves the
      prior flat mapping behavior)
- [x] Rich mapping entries coexist with plain strings
      (`test_same_name_service_entries_are_additive` shows a string-first then mapping-second authoring pattern renders
      into a superset of hosts without replacing the baseline)
- [x] Generic `readonly: true` narrows emitted rules to `GET`/`HEAD` and omission keeps readwrite behavior
      (service catalog emits `methods: [GET, HEAD]` for simple services when `readonly: true`; matcher remains generic)
- [x] GitHub `git` readonly keeps clone/fetch working (`git-upload-pack`) and excludes push (`git-receive-pack`)
      (`test_readonly_github_repo_scoped_policy_enforces_clone_and_blocks_push` exercises the full matcher path using
      the rendered policy IR)
- [x] Invalid service config produces actionable errors
      (catalog validates `name`, `merge_mode`, `readonly`, `repos`, and `surfaces` with context-aware messages; covered
      by `ServiceCatalogNormalizeTests`)
- [x] Service definitions are testable in isolation
      (`images/proxy/tests/test_service_catalog.py` loads the catalog directly and does not import the renderer)
- [x] Matcher and addon remain service-agnostic
      (no GitHub branches added to `policy_matcher.py`; the catalog emits only canonical host-record fragments that feed
      into the existing merge pipeline)
- [x] Same-name service entries are additive by default
      (covered by `test_same_name_service_entries_are_additive`)
- [x] `merge_mode: replace` discards prior expansions for the service name
      (covered by `test_service_merge_mode_replace_discards_baseline_expansion` and
      `test_service_merge_mode_replace_preserves_unrelated_domain_rules`)
- [x] Docs and examples describe the richer shape
      (`docs/policy/schema.md` services section rewritten; `docs/policy/examples/github-repos.yaml` added;
      `internal/embeddata/templates/policy.yaml` points at the new catalog module)

Test runs after the simplify pass:

- `go test ./...` - all packages pass
- `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` - 56 tests pass

### Learnings

- A Python-backed service catalog earns its keep as soon as one rich service needs semantic expansion; a declarative
  catalog file would have added loader complexity without changing where the hard validation logic has to live.
- Normalizing service entries into a single `{name, merge_mode, options}` shape keeps the renderer call site tiny: the
  catch-all host expander and the GitHub expander both consume the same normalized record, and the renderer only has to
  know how to fold expansion output back through its existing host-record merge.
- Tracking `state["service_rules"][name][host] = [rule_identity, ...]` is the right grain for service-level
  `merge_mode: replace`. Per-rule identities let the renderer drop just the fragments a service contributed without
  touching neighboring authored `domains` rules, and empty hosts get pruned from the iteration order so the replacement
  looks like the service never ran.
- The GitHub `git` readonly exception is cheaply contained inside the catalog: readonly clone/fetch expands to the
  smart-HTTP `git-upload-pack` rules (`info/refs?service=git-upload-pack` plus `POST /{owner}/{name}.git/git-upload-pack`),
  and readwrite adds the matching `git-receive-pack` pair. Keeping that mapping service-local avoided inventing a new
  matcher concept.
- The catalog output is canonical on purpose; re-normalizing it inside the renderer is wasteful defensive code and
  muddies the abstraction boundary between "catalog emits canonical IR" and "renderer normalizes authored input."
- Splitting copy-pasted per-repo rule construction into `_github_api_rules_for_repo` / `_github_smart_http_pair` /
  `_github_git_rules_for_repo` made the readonly-vs-readwrite branches legible without introducing an unnecessary
  abstraction layer.

### Follow-up Items

- `m14.5` should pick up broader migration guidance, lock-down of the complete example set, and troubleshooting
  coverage for the richer `services` shape.
- If future services duplicate the pattern of "named surfaces plus scoped selectors," revisit whether the per-service
  Python expander can be factored into a shared helper; `m14.3` deliberately resisted that abstraction until a second
  rich service exists.
- Downstream `m15` still owns the GitHub REST wrapper work; the repo-scoped `api` surface added here intentionally
  stops at URL-shape filtering and leaves credential-aware behavior to that milestone.
