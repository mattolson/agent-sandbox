# Execution Log: m15.1 - Policy Injection Schema

## 2026-05-03 02:42 UTC - Closed schema open questions

Resolved the two open schema questions before implementation.

**Decision:** `on_existing_header` supports `fail` and `replace`, with `fail` as the default.

**Decision:** Secret IDs are restricted to `[A-Za-z0-9._-]+` for m15.1. That keeps IDs path-safe and backend-neutral
while still allowing readable names like `github.agent-sandbox.push-token`.

## 2026-05-03 02:37 UTC - Initial task plan

Created the `m15.1` task plan from the milestone breakdown and reviewed the existing renderer and matcher code paths.

**Decision:** Keep `m15.1` centered on the rendered policy schema and loader compatibility. Runtime secret loading,
secret resolution, request mutation, GitHub service shorthand, and docs stay in later m15 tasks.

**Observation:** `images/proxy/addons/policy_matcher.py` currently rejects unknown rule keys, so a rendered `inject`
field would break policy loading unless this task includes a narrow matcher data model/loader update. That update should
not change request allow/block behavior yet.
