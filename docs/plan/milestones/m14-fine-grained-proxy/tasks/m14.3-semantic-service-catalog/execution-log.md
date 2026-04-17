# Execution Log: m14.3 - Semantic Service Catalog

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
