# Execution Log: m14.3 - Semantic Service Catalog

## 2026-04-17 16:10 UTC - Completed task and verified acceptance criteria

Re-ran `go test ./...` and `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
after the simplify pass. Both suites remain green (Go packages all pass; 56 Python tests pass). Walked through every
acceptance criterion and confirmed coverage in the task outcome section.

**Decision:** Mark the task complete on the back of the Python test suite plus Go CLI tests rather than spinning up a
full local proxy build. The Python tests exercise the catalog directly, through the renderer, and through the generic
matcher, which is the full render-to-runtime path this task was supposed to prove.

**Learning:** End-to-end confidence for this slice came from the policy-matcher integration test that drives the
rendered policy IR through the real matcher. That shape is worth keeping as the default integration proof for future
service expansions.

## 2026-04-17 15:45 UTC - Ran `/simplify` over the changed files

Launched three parallel review agents (reuse, quality, efficiency) across the catalog, renderer, tests, docs, and
template changes. Addressed three actionable findings and skipped the rest as false positives or stylistic noise.

**Issue:** `apply_service_expansion` re-ran `normalize_host_pattern` and `normalize_rule` over the catalog's output.
**Solution:** Dropped the re-normalization loop. The catalog already produces canonical IR, so the renderer should
trust that boundary instead of defensively repeating validation. Simplified `apply_service_expansion(state, expansion)`
to feed records straight through `apply_host_record` while tracking rule identities for `merge_mode: replace`.

**Issue:** `_expand_github_service` contained near-duplicate readonly vs readwrite blocks for both API and Git
surfaces.
**Solution:** Extracted `_github_api_rules_for_repo`, `_github_smart_http_pair`, and `_github_git_rules_for_repo`
helpers. The expander now builds API and Git records by iterating repos and delegating to the helpers; the readonly
branch simply skips the `git-receive-pack` pair.

**Issue:** Inline string literals (`"api"`, `"git"`, `"replace"`, `"git-upload-pack"`, `"git-receive-pack"`, write
methods) encouraged copy-paste drift.
**Solution:** Promoted to module constants (`SURFACE_API`, `SURFACE_GIT`, `MERGE_MODE_REPLACE`,
`GIT_UPLOAD_PACK_SERVICE`, `GIT_RECEIVE_PACK_SERVICE`, `WRITE_METHODS`) and reused them throughout the catalog.

**Decision:** Skipped the agent suggestion to widen catalog exports for unrelated cleanup in `render-policy`. The
milestone boundary keeps that tree owned by the renderer; a broader restructure belongs in `m14.5` once more rich
services exist.

## 2026-04-17 13:30 UTC - Wired the renderer through the catalog and landed GitHub expansion

Replaced the flat `SERVICE_DOMAINS` dict inside `images/proxy/render-policy` with an import of the new
`service_catalog.py` module. Added `state["service_rules"]` bookkeeping plus a `discard_service_contributions` helper
so `merge_mode: replace` can drop prior expansions for the same service name before the new fragments enter
host-record merging. The renderer now expands each `services` entry via `expand_service_entry` and feeds every host
record through the existing `apply_host_record` merge path.

Implemented the GitHub expansion in `service_catalog.py`:

- plain-string `github` entries emit the baseline `github.com`, `*.github.com`, `githubusercontent.com`,
  `*.githubusercontent.com` host records with host-wide catch-all rules (readonly narrows them to GET/HEAD).
- mapping entries with `repos` plus `surfaces` emit the repo-scoped API and smart-HTTP rules described in the plan,
  with readonly expanding only the `git-upload-pack` clone/fetch pair and readwrite adding `git-receive-pack`.

**Decision:** Canonical storage of `repos` is a list of `(owner, name)` tuples rather than `"owner/name"` strings.
Tuple form avoids a second string split inside the expander and makes validation errors point at the right field.

**Decision:** Surface expansion is order-independent on input but deterministic on output: `api` records precede `git`
records and repos expand in authored order, with de-dupe on canonical `owner/name` identifiers.

## 2026-04-17 11:45 UTC - Built out the test trio and docs surface

Added `images/proxy/tests/test_service_catalog.py` with 22 unit tests split between normalization and expansion.
Extended `test_render_policy.py` with five renderer integration cases covering repo-scoped rendering, additive
same-name entries, `merge_mode: replace` discard plus unrelated-domain preservation, and plain-string GitHub baseline
expansion. Added `PolicyMatcherGithubServiceIntegrationTests.test_readonly_github_repo_scoped_policy_enforces_clone_and_blocks_push`
to prove the rendered IR flows through the generic matcher and enforces clone-capable readonly scoping without any
GitHub-specific matcher branch.

Updated `docs/policy/schema.md` with the richer `services` authoring shape, added
`docs/policy/examples/github-repos.yaml`, updated `internal/embeddata/templates/policy.yaml` to point at the new
catalog module, and refreshed the `add-agent` skill reference from `SERVICE_DOMAINS` to `SIMPLE_SERVICE_HOSTS` in
`service_catalog.py`.

**Learning:** `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy tests. System Python lacks the
`yaml` module, and the proxy virtualenv ships the same dependencies that run in the container.

**Learning:** Loading `render-policy` in tests requires `SourceFileLoader` because the script has no `.py` suffix;
keep that helper centralized so future proxy tests do not reinvent it.

## 2026-04-17 04:55 UTC - Closed the remaining planning questions

Updated the `m14.3` task plan to remove the remaining open design questions. The plan now explicitly keeps the service
catalog as Python-backed renderer logic for this task, requires `m14.3` docs to cover the authored service surface
users need to rely on, and defers migration polish and broader documentation lock-down to `m14.5`.

**Decision:** Keep the catalog in Python for `m14.3`. Do not add a separate declarative catalog file yet.

**Decision:** Document the authored service surface in `m14.3`, including `repos`, `surfaces`, `readonly`,
service-level `merge_mode: replace`, merge semantics, and the GitHub `git` readonly exception.

**Decision:** Do not invent a broader abstraction beyond per-service semantic expansion for `m14.3`. Revisit only if
later services show the boolean `readonly` model is no longer sufficient.

## 2026-04-17 04:36 UTC - Switched the GitHub selector from singular `repo` to a `repos` list

Updated the `m14.3` task plan to support a `repos` list instead of a singular `repo` field. The common case is still a
one-item list for the current workspace repo, but the incremental implementation cost is low because expansion can stay
linear: validate each `owner/name` entry and emit the same repo-scoped rule families for each listed repo.

**Decision:** Use `repos: [owner/name, ...]` as the canonical GitHub selector shape rather than a singular `repo`
field.

**Decision:** Treat multi-repo support as linear expansion, not as a new merge or matching concept.

**Supersedes:** The 2026-04-16 16:18 UTC decision that kept the first GitHub repo selector singular.

## 2026-04-17 04:15 UTC - Replaced the enum-style method knob with a boolean `readonly` flag

Updated the `m14.3` task plan to use `readonly: true` instead of `method_profile: readonly`. The authored surface is
now simpler: `readonly: true` enables narrowed or semantic read-only expansion, while omitted `readonly` or
`readonly: false` defaults to the service's normal readwrite behavior.

**Decision:** Use a boolean `readonly` flag rather than an enum-style `method_profile` field.

**Decision:** Treat omitted `readonly` and `readonly: false` as the same readwrite default.

## 2026-04-16 16:23 UTC - Made GitHub `git` readonly semantic enough for clone and fetch

Updated the `m14.3` task plan after deciding that GitHub Git-over-HTTPS `readonly` must support clone and fetch, even
though those workflows use `POST` to `git-upload-pack`. The plan now treats that as service-side semantic expansion in
the GitHub `git` surface rather than as a generic matcher or global method-profile rule.

**Decision:** Keep `method_profile` as the authored knob, but let the GitHub `git` surface map `readonly` to the
specific smart-HTTP rule bundle needed for clone and fetch.

**Decision:** `readonly` for GitHub `git` includes `info/refs?service=git-upload-pack` discovery plus `POST` to
`git-upload-pack`, while still excluding `git-receive-pack`.

## 2026-04-16 16:18 UTC - Expanded GitHub scope to include Git smart-HTTP and made repo selection singular

Updated the `m14.3` task plan after deciding that GitHub Git-over-HTTPS belongs in this task alongside the repo-scoped
REST API surface. The plan now treats GitHub as a single-repo service entry with a singular `repo` field and explicit
`api` plus `git` surfaces.

**Decision:** Keep the first GitHub repo selector singular as `repo: owner/name`. Multi-repo service entries are
deferred because the common sandbox shape is one workspace repo per container.

**Decision:** Include Git smart-HTTP in `m14.3` rather than deferring it. The first GitHub service expansion should
emit URL-visible single-repo rules for both `api.github.com` and the canonical `github.com/{owner}/{repo}.git` paths.

**Decision:** Keep `method_profile` literal. `readonly` still means `GET` plus `HEAD`, even though Git clone or fetch
use `POST` to `git-upload-pack`. Do not pretend the generic method profile captures higher-level Git operation intent.

## 2026-04-16 16:14 UTC - Resolved the `readonly` method-profile semantics

Closed the remaining method-profile question in the `m14.3` task plan. `readonly` now explicitly means `GET` plus
`HEAD`, while `readwrite` continues to mean "preserve the service's normal emitted methods."

**Decision:** Keep `readonly` narrow and explicit as `GET` plus `HEAD`. Do not treat it as a fuzzy "safe methods" set.

## 2026-04-16 15:38 UTC - Locked service-level merge semantics and added generic method-profile planning

Updated the `m14.3` task plan after design discussion about generic service options. The plan now treats richer service
entries with the same `name` as additive by default after expansion, and introduces explicit service-level
`merge_mode: replace` semantics that discard prior expansions for that service name before normal host-record merging.

The plan also now includes a generic `method_profile` option at render time. `readwrite` preserves the service's normal
emitted methods, while `readonly` narrows emitted rules without teaching the matcher any new service-specific logic.

**Decision:** Service configs are not merged field by field. Each authored service entry expands independently, then the
expanded fragments participate in the existing host-record merge path.

## 2026-04-16 15:12 UTC - Drafted the task plan and locked the intended boundary

Reviewed the `m14` milestone plan, project learnings, decision record `005`, the current `render-policy`
implementation, the `m14.2` matcher boundary, and the downstream `m15` GitHub wrapper goals. The main planning
conclusion is that `m14.3` should not push GitHub-specific behavior into the matcher. Service semantics belong at
render time and should compile into the same canonical host-record IR that authored `domains` already use.

**Issue:** The current inline `SERVICE_DOMAINS` map can only emit host-wide trust. That blocks repo-scoped GitHub
policy authoring and creates pressure to add service-specific request logic in the runtime.

**Decision:** Plan `m14.3` around a dedicated renderer-side service catalog boundary plus direct catalog tests, keeping
`policy_matcher.py` generic.

**Open Question:** Additive host-record merging does not automatically narrow an earlier broad service declaration. The
task must resolve whether richer service entries get explicit replacement semantics or whether scoped service entries are
documented as additive only.
