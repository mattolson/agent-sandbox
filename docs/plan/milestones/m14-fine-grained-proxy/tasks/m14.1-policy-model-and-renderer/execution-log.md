# Execution Log: m14.1 - Policy Model and Renderer

## 2026-04-12 06:07 UTC - Renderer, tests, and docs updated for the canonical host-record IR

Implemented the `m14.1` renderer contract in `images/proxy/render-policy`, added direct renderer tests under
`images/proxy/tests/`, added a dedicated `proxy-tests.yml` workflow, updated the minimal enforcer loader compatibility
in `images/proxy/addons/enforcer.py`, and rewrote the policy schema docs and templates to match the new authored and
rendered shapes.

**Decision:** Treat legacy `services` plus string `domains` policies as authoring-compatible and semantically stable,
not byte-for-byte rendered-output stable. The renderer now intentionally compiles `services` away into canonical host
records.

**Decision:** Fail fast on unknown service names and invalid rich-rule shapes instead of silently skipping them. This is
the safer boundary for a security-sensitive renderer.

**Issue:** The current workspace does not have a Python runtime or Docker CLI, so the new proxy-side Python tests
cannot be executed locally here.

**Solution:** Added direct renderer unit tests plus a dedicated GitHub Actions workflow for them, and used `go test
./...` as the executable local verification that was still available in this container.

## 2026-04-12 05:55 UTC - Execution started from the approved task plan

Revalidated the current worktree after the interrupted start and confirmed the only pending change was the prior
planning-approval log entry. Began implementation with the renderer as the primary surface, since the current
`render-policy` still treats `domains` as a simple string union and cannot support rich host records safely.

**Decision:** Start by replacing the renderer merge model with a canonical host-record IR and only then make the
minimal enforcer and documentation changes needed around it.

## 2026-04-12 05:38 UTC - Planning approved, implementation intentionally deferred

The user approved the current `m14.1` task plan after the schema review passes on services, layer precedence, host
specificity, shorthands, and trust boundaries.

**Decision:** Treat the current task plan as the approved execution baseline for `m14.1`.

**Decision:** Do not begin implementation yet. The task is ready to start, but execution remains explicitly paused until
the user asks to proceed.

## 2026-04-11 05:44 UTC - Separated layer merge order from host-pattern precedence

Updated the task plan after reviewing how overlapping host records from different policy layers should behave.

**Decision:** Distinguish merge-time and match-time behavior explicitly.

- Layers merge first in the existing order: service expansion or baseline, shared policy, agent policy, then
  devcontainer policy.
- Host records with the same normalized host identity merge across layers, with additive behavior by default and
  `merge_mode: replace` as the escape hatch.
- Host records with different identities coexist in the rendered policy.
- Only after rendering do match-precedence rules apply: exact host beats wildcard host, and among wildcards the longest
  suffix wins.

**Example:** If shared policy contains `api.github.com` and agent policy contains `*.github.com`, both records survive
rendering. Requests to `api.github.com` use the exact-host record; requests to other matching subdomains use the
wildcard record.

## 2026-04-11 05:44 UTC - Defined precedence for overlapping host patterns

Updated the task plan after reviewing how overlapping exact and wildcard host records should behave.

**Decision:** Allow overlapping host patterns, but resolve them by specificity at match time. Exact host records beat
wildcard host records, and among wildcard records the longest matching suffix wins.

**Rationale:** In an allow-only model, naive union semantics would let broad wildcard rules silently widen narrow
exact-host restrictions. Specificity-based matching keeps wildcard convenience without weakening repo- or host-specific
policy.

## 2026-04-11 05:44 UTC - Unified service expansion with the canonical rendered host IR

Updated the task plan after a review pass surfaced a real dual-model risk: keeping symbolic `services` in the rendered
policy while normalizing `domains` into rich host records would leave `m14.2` with two policy shapes to interpret.

**Decision:** Treat `services` as an authored convenience only. The renderer should expand them into the same canonical
host-record IR used for authored `domains` entries.

**Decision:** Refined that model further: `services` are semantic authored shortcuts, not another spelling of generic
host records. Service declarations may have service-specific option schemas, while the renderer still compiles them into
the same flattened host-record IR.

**Decision:** Rich service-specific authored schemas, such as GitHub repo scoping, are deferred to `m14.3`. `m14.1`
only fixes the rendered IR contract and the expansion boundary.

**Decision:** User-authored host records should be able to override service-expanded host records through the same
`merge_mode: replace` behavior used elsewhere in the layered merge model.

## 2026-04-11 05:44 UTC - Kept the policy model allow-only

Recorded an explicit scope boundary after discussing whether the rule model should support `allow` versus `deny`.

**Decision:** Keep `m14.1` allow-only. Do not add rule polarity or "allow everything on this host except these"
semantics.

**Rationale:** The current security posture is default-deny plus explicit allow. Adding deny semantics early would
weaken that mental model, complicate merge behavior, and make policy precedence harder to explain before the allow-only
shape is even implemented.

## 2026-04-11 05:44 UTC - Narrowed the remaining Go-scaffolding note

Cleaned up the last stale open question about Go schema tolerance.

**Decision:** Do not treat Go scaffolding as an active `m14.1` blocker. Keep the richer schema work focused on
user-owned policy files and the proxy-side renderer unless managed policy generation later proves it needs to emit or
preserve rich rules inside `m14`.

## 2026-04-11 05:44 UTC - Closed most remaining schema-shape open questions

Updated the draft policy spec with the user's answers on merge directives, wildcard semantics, shorthands, and query
normalization.

**Decision:** Rename the authored host-merge directive to `merge_mode: replace`.

**Decision:** Omitted authored `scheme` or `schemes` means both `http` and `https`. Omitted authored `method` or
`methods` means any method.

**Decision:** Add singular shorthands `scheme` and `method`. If the singular and plural forms are both supplied, the
renderer should warn on `stderr`, merge them, normalize them, and de-duplicate them.

**Decision:** Accept scalar shorthand for `query.exact.<name>: value` and normalize it to a single-item list in the
rendered policy.

**Decision:** Exact query matching should ignore pair ordering and compare normalized per-key value lists.

**Issue:** Warnings during rendering can corrupt machine-readable output if they go to `stdout`.

**Solution:** Any renderer warnings for conflicting shorthand forms should go to `stderr` so `agentbox policy config`
can still emit valid YAML on `stdout`.

## 2026-04-11 05:44 UTC - Made authored method names case-insensitive

Updated the draft policy spec after the user asked for case-insensitive method matching to make authoring easier.

**Decision:** Accept authored method names case-insensitively and normalize them to uppercase in the rendered policy.

**Rationale:** This keeps authoring forgiving while still giving the renderer one canonical form for merge behavior,
deduplication, and downstream enforcement.

**Decision:** Keep the field name plural as `methods`. Do not add a separate `method` alias unless review later shows a
strong reason for it.

## 2026-04-11 05:44 UTC - Switched rule example ordering to schemes, methods, path, query

Updated the draft examples after the user reversed the earlier preference for listing `path` first.

**Decision:** In examples and docs, list rule fields in request-matching order: `schemes`, `methods`, `path`, then
`query`.

**Note:** `method` is not part of the URI strictly speaking, but the new ordering is still the clearer request-matcher
presentation for this policy format.

## 2026-04-11 05:44 UTC - Made the non-empty rule requirement explicit

Clarified the draft rule contract after the user asked whether `path` is optional and whether all rule elements are
optional.

**Decision:** `path`, `schemes`, `methods`, and `query` are each optional individually, but a rule must not be empty
after normalization.

**Rationale:** An all-optional rule would act like silent host-wide trust. That is too broad to encode as an empty
object. If the policy wants broad trust, it should say so explicitly.

**Decision:** Host-wide allow remains representable, but only through an explicit catch-all rule shape such as
`schemes: [https]` or the renderer-generated catch-all for legacy string host entries.

## 2026-04-11 05:44 UTC - Made path primary in the rule examples

Refined the draft policy examples after the user asked whether each rule is implicitly for a single path and requested
that `path` be listed first when present.

**Decision:** Treat each rule as one conjunction of constraints with at most one path matcher. If a host needs multiple
allowed path alternatives, express them as multiple rules instead of a compound path list inside one rule.

**Decision:** In examples and docs, list `path` first in rule objects when present, since it is the primary
rule-shaping field in the current policy design.

## 2026-04-11 05:44 UTC - Added schemes to the policy-record proposal

Updated the draft policy spec after the user asked whether protocol should be part of the rule shape.

**Decision:** Add `schemes` to rule records now rather than treating `http` and `https` as equivalent by omission.
Use `schemes` rather than `protocol` so the field stays aligned with HTTP policy rather than implying broader
transport-level support.

**Issue:** The earlier draft used `rules: []` as the rendered meaning of "allow the whole host." That shape becomes
awkward once `schemes` exists, because there is nowhere to say "allow the whole host, but only for HTTPS."

**Solution:** The updated proposal treats rendered host-wide allow as an explicit catch-all rule with concrete
`schemes`, usually `[http, https]` for legacy string entries.

**Decision:** This is still a spec-only update. No renderer or enforcement implementation has started yet.

## 2026-04-11 05:44 UTC - Recorded the trust boundary for matched URL rules

Recorded a formal planning decision after discussing exfiltration risk on allowed endpoints.

**Decision:** For `m14`, a matched URL rule implies that the endpoint is trusted to receive the full request. `m14`
will constrain host, method, path, and query only. Header and request-body inspection are explicitly deferred to future
work.

**Rationale:** Treating headers as mandatory for exfiltration control while still ignoring request bodies would create a
misleading boundary. The cleaner line is to keep `m14` focused on URL-shape restriction and record the trust
assumption explicitly.

**Follow-up:** Added decision record `005-trust-url-matches-until-deeper-request-inspection.md` and updated the `m14`
milestone/task plans to match it.

## 2026-04-11 05:44 UTC - Policy record proposal updated from user feedback

Folded the user's schema-direction answers into the task plan and turned them into a concrete record-shape proposal for
review before renderer changes.

**Decision:** Use `host` as the canonical key for rich domain entries. The old authored string form stays as a
compatibility input, but rendered policy should normalize `domains` entries to rich objects.

**Decision:** Keep additive merge semantics by default for host records, with rule de-duplication. Add a host-level
escape hatch via authored `merge: replace`, which the renderer consumes during layering and strips from the rendered
output.

**Decision:** Add Python unit tests for proxy-image Python code and a GitHub workflow for them, but defer that work
until after the policy record shape is approved.

**Issue:** The escape hatch needs a concrete spelling now. A vague "special-purpose key" is not enough to implement or
document.

**Solution:** Proposed `merge: replace` as the authored-only control field. It is short, readable in YAML, and leaves
room for future merge modes without forcing a boolean one-off like `replace: true`.

## 2026-04-11 05:44 UTC - Query matching requirement added to the schema proposal

Added a concrete query-record proposal after the user called out two required cases:

- "GET request with no query params"
- "GET request with a specific value for a specific query param"

**Issue:** A vague `query` object is not enough. The schema has to distinguish between "no query constraint" and "the
query string must be empty," or the first requested case cannot be expressed safely.

**Solution:** Propose an explicit query match mode with `query.exact`. In this shape:

- omitted `query` means no query constraint
- `query.exact: {}` means no query params allowed
- `query.exact.<name>: [value]` means an exact query match on that param map

**Decision:** Keep the first version query semantics narrow and exact-only. That satisfies the current requirement
without prematurely adding looser subset or contains modes that would complicate merge and enforcement semantics.

## 2026-04-11 05:44 UTC - Initial planning completed

Reviewed the `m14` milestone plan, accumulated project learnings, and the current policy implementation surfaces in the
proxy, docs, templates, and Go scaffolding.

The main planning conclusion is that `m14.1` is not just a renderer tweak. The current system assumes `domains` is a
list of strings in at least three places:

- `images/proxy/render-policy` validates and merges `domains` as a string list
- `docs/policy/schema.md` documents only the string-list format and the current union merge semantics
- `internal/scaffold/policy.go` and related tests still model policy files as `services []string` plus `domains []string`

**Issue:** If rich request rules are added under `domains` without first defining a canonical rendered IR and a stable
merge identity, layered policy files will produce ambiguous behavior. List-order merge is not defensible for
security-sensitive rules.

**Solution:** Plan around a normalized host-keyed policy IR, keep authored YAML backward compatible, and require direct
tests for the renderer itself instead of relying only on higher-level CLI coverage.

**Decision:** Keep `services` symbolic in `m14.1` and defer richer service expansion to `m14.3`. The current task
should solve schema and merge semantics first, not pull semantic service bundles forward early.

**Learning:** The existing flat `services` plus `domains` schema is now duplicated across Python docs and Go test
helpers. Even if the runtime merge logic stays in Python, schema evolution will spill into Go-facing docs and test
surfaces immediately.
