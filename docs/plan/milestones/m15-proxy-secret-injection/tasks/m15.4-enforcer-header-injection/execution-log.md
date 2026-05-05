# Execution Log: m15.4 - Enforcer Header Injection

## 2026-05-04 02:25 UTC - Implementation complete

Implemented request-time proxy header injection. The matcher now attaches matched rule index and runtime transform
metadata to allowed request decisions, and transformed HTTPS rules force request inspection instead of taking the
CONNECT fast path. The enforcer lazily constructs the secret resolver, resolves secrets per matching request, applies
`bearer` and `basic` transforms, handles existing-header `fail` and `replace`, blocks on resolver or transform errors,
and emits redacted `header_injection` audit events.

Added unit coverage for successful injection, unmatched requests, untransformed rules, existing-header conflicts,
case-insensitive replacement, resolver failures, redaction, and requestheaders/request double-hook behavior. Extended
the integration harness to pass proxy env vars and custom request headers, then added real-proxy tests proving upstream
header injection and fail-closed conflict behavior.

Verified with:

- `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- `go test ./...`

**Decision:** Injection success uses a separate `type: "header_injection"` event. Blocking failures use
`reason: "header_injection_failed"` with redacted `detail` values.

**Decision:** Missing or invalid `AGENTBOX_SECRET_SOURCE` is lazy. It fails only a matching transformed request, not
proxy startup or unrelated allowed requests.

**Learning:** Header injection changes CONNECT semantics for transformed HTTPS rules. Any rule that may need request
mutation must force request inspection, or the proxy might allow a tunnel before it can mutate headers.

## 2026-05-04 02:14 UTC - Initial task plan

Created the m15.4 task plan from the milestone breakdown and reviewed m15.1 transform metadata, m15.2 secret resolver
helpers, m15.3 runtime secret mounting, the current enforcer request lifecycle, matcher decision model, unit tests, and
real-proxy integration harness.

**Decision:** Keep m15.4 focused on runtime request mutation. Policy schema, service catalog auth shorthand, client
compatibility shims, and user-facing docs stay in later m15 tasks.

**Decision:** The matcher must expose the matched rule context to the enforcer, likely as a matched rule index plus
runtime-only transform metadata on allowed request decisions. Host-level matching alone is insufficient and would risk
applying a credential to the wrong same-host rule.

**Decision:** Prefer lazy resolver construction and request-time resolution. A policy without matching transformed
requests should not fail just because `AGENTBOX_SECRET_SOURCE` is missing or invalid, but a matching transformed request
must fail closed if the resolver cannot produce the secret.

**Observation:** The existing requestheaders/request double-hook pattern already stores decisions on the flow to avoid
duplicate block handling. m15.4 should reuse that guard so header injection runs once even if both hooks fire.
