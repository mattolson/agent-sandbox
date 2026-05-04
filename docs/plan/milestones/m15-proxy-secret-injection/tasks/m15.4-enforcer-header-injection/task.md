# Task: m15.4 - Enforcer Header Injection

## Summary

Inject configured headers at request time after a rule with request transform metadata matches.

## Scope

- Resolve referenced secrets through the configured resolver
- Apply `basic` and `bearer` transforms and set configured request headers
- Fail closed when the request already contains the injected header unless the rule explicitly permits replacement
- Emit redacted audit logs that identify the secret ID and matched rule, not the value
- Honor the freshness semantics defined by the resolver, so secret rotation behavior is predictable
- Exclude GitHub service shorthand
- Exclude client compatibility shims, policy authoring changes, service catalog auth, and user-facing docs

## Acceptance Criteria

- [ ] Proxy/enforcer tests prove injected headers reach a fake upstream only for matched rules
- [ ] Tests prove unmatched requests do not receive injected headers
- [ ] Existing-header behavior is covered for fail and explicit replacement modes
- [ ] Logs, errors, and rendered decisions never include the secret value

## Applicable Learnings

- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs.
- Thick unit coverage does not substitute for integration wiring coverage. m15.4 needs unit tests for the enforcer logic
  and integration coverage proving a real proxy forwards the mutated header upstream.
- For proxy addons that can block requests before a response hook runs, storing the policy decision on the flow avoids
  later response logging from accidentally relabeling blocked requests as allowed.
- Shared proxy helper modules used by both `render-policy` and addons must account for the image layout. The enforcer
  should import `secret_resolver.py` from the proxy library path in the image and from `images/proxy/` in local tests.
- Rule-scoped policy metadata should stay rule-scoped through matching. Header injection must use the exact rule that
  matched the request, not host-level metadata.
- File-backed secret readers resolve at request time, so m15.4 should call the resolver when a matching request is being
  mutated rather than caching secret values in the matcher or enforcer.
- File-backed secret readers return warnings for unsafe permissions. Those warnings are actionable but must remain
  redacted and must not include secret values.

## Plan

### Files Involved

- `images/proxy/addons/policy_matcher.py` - extend request decisions with the matched rule index and rule-scoped
  transform metadata while keeping logs and serialized flow metadata redacted
- `images/proxy/addons/enforcer.py` - import the secret resolver, resolve and render header values at request time,
  mutate request headers before upstream forwarding, fail closed for conflicts or resolution errors, and emit redacted
  audit events
- `images/proxy/tests/test_policy_matcher.py` - cover matched-rule transform metadata on allowed request decisions
- `images/proxy/tests/test_enforcer.py` - unit coverage for injection, unmatched requests, existing-header fail/replace,
  secret resolution failures, duplicate-hook behavior, and redacted logs
- `images/proxy/tests/integration/harness.py` - allow integration tests to pass custom proxy environment variables and
  request headers
- `images/proxy/tests/integration/test_proxy_enforcement.py` - add a real-proxy HTTP integration test proving a fake
  upstream receives injected headers only for matched requests and never sees values when injection fails

### Approach

Keep policy rendering unchanged. m15.1 already renders rule-scoped request transform metadata and m15.2 already provides
`SecretResolver.from_env()` plus `render_header_value()`. m15.4 should connect those pieces inside the runtime request
path only.

The matcher needs to expose enough request-match context for the enforcer to mutate the request correctly. Extend
`PolicyDecision` for allowed request decisions with:

- `matched_rule_index` for audit/debug context
- `rule_transform` or equivalent runtime-only transform metadata for immediate injection

Do not serialize secret values into `PolicyDecision.to_metadata()`. Flow metadata can store `matched_rule_index` and
redacted injection summaries if useful for response logging, but it should not store resolved header values or
`SecretValue` objects.

The enforcer should apply injection in `_handle_request_decision()` after a request is allowed and before storing the
decision. That keeps the mutation shared by `requestheaders()` and the `request()` fallback while using the existing
stored-decision guard to avoid duplicate injection. If a prior blocked decision is already stored, no injection should
run.

Header mutation should follow this contract:

- If the matched rule has no request transform, leave headers unchanged.
- If the matched rule has a request transform, resolve each referenced secret at request time.
- For `bearer`, set the configured header to `Bearer <secret>`.
- For `basic`, set the configured header to `Basic <base64(username:secret)>`.
- Treat header names case-insensitively when checking for existing headers.
- If an injected header already exists and `on_existing_header` is `fail`, block the request before upstream forwarding.
- If an injected header already exists and `on_existing_header` is `replace`, overwrite it.
- If secret resolution or transform rendering fails, block the request before upstream forwarding.

Blocking due to injection failure should reuse the existing synthetic `403` path and stored decision pattern so response
logging does not later report it as allowed. Add a request-phase reason such as `header_injection_failed` with a
redacted audit field that identifies the header name and secret ID. Existing-header conflicts should have a distinct
reason or detail such as `existing_header_present`.

Audit events should be useful but safe. For successful injection, emit a separate redacted event or enrich the allowed
decision log with fields such as:

- `type: "header_injection"`
- `action: "applied"`
- `host`, `matched_host`, `matched_rule_index`
- `headers`: header names with secret IDs and transform types
- permission warning codes/paths from `SecretResolutionWarning`, if any

Never log the resolved secret value or the rendered header value. Tests should include a sentinel secret and assert it
does not appear in logger output, exception strings, decision metadata, or integration harness logs.

Resolver construction should be lazy. Policies without matching transforms should not require `AGENTBOX_SECRET_SOURCE`
to be valid. A request matching a transform with a missing or invalid resolver source should fail closed.

### Implementation Steps

- [ ] Extend `PolicyDecision` with request-match rule context needed for injection
- [ ] Update `PolicyMatcher.evaluate_request()` to attach the matched rule index and transform metadata to allowed
      request decisions
- [ ] Ensure `PolicyDecision.to_metadata()` / `from_metadata()` remain redacted and do not store secret values
- [ ] Add enforcer import/path handling for `secret_resolver.py` in both image and local test layouts
- [ ] Add lazy resolver construction in `PolicyEnforcer`
- [ ] Implement request-time injection for matched request transforms
- [ ] Implement existing-header conflict handling for `fail` and `replace`
- [ ] Fail closed for resolver source errors, missing secret files, invalid secret bytes, or transform rendering errors
- [ ] Add redacted audit logging for successful injection, permission warnings, and injection failures
- [ ] Add unit tests for successful bearer and basic injection
- [ ] Add unit tests proving unmatched requests and untransformed rules do not inject headers or require a resolver
- [ ] Add unit tests for existing-header fail and replace behavior, including case-insensitive header names
- [ ] Add unit tests proving requestheaders/request double-hooking does not inject twice
- [ ] Add unit tests proving secret values are absent from logs, errors, and stored decision metadata
- [ ] Extend the integration harness to pass `AGENTBOX_SECRET_SOURCE` and custom request headers
- [ ] Add real-proxy integration coverage for upstream-observed injection and blocked conflict behavior
- [ ] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [ ] Run `go test ./...` as a repo-wide sanity check

### Open Questions

- Should missing or invalid `AGENTBOX_SECRET_SOURCE` fail proxy startup when a loaded policy contains transforms, or
  fail closed only when a matching transformed request arrives? Recommended default: lazy request-time failure so
  untransformed and unmatched traffic is not coupled to secret backend availability.
- Should injection success be logged as a separate `type: "header_injection"` event, or folded into the normal allowed
  request event? Recommended default: separate event for mutation details, while keeping the normal allowed/blocked
  decision schema stable.
- What exact blocked reason should be used for injection failures? Recommended default: `header_injection_failed` with
  a redacted `detail` field such as `existing_header_present`, `secret_resolution_failed`, or `transform_failed`.

## Outcome

### Acceptance Verification

Pending implementation.

### Learnings

Pending implementation.

### Follow-up Items

Pending implementation.
