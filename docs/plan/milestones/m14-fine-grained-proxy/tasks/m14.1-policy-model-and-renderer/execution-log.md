# Execution Log: m14.1 - Policy Model and Renderer

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
