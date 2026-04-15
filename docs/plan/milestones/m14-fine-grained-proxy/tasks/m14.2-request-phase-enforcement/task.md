# Task: m14.2 - Request-Phase Enforcement

## Summary

Move enforcement to a matcher that can inspect decrypted HTTPS requests and apply scheme, method, path, and query
rules while preserving the existing host-only CONNECT fast path.

## Scope

- Implement shared request matching for HTTP and MITM'd HTTPS traffic
- Keep CONNECT-time blocking for policies that only need hostname checks
- Define path and query matching semantics tightly enough to be testable and reviewable
- Add structured allow and block logs that include request details and the reason a rule matched or failed
- Ensure HTTP and HTTPS share one policy evaluation path once the request is available
- Compile the rendered host-record IR from `m14.1` into one runtime matcher model instead of interpreting policy
  ad hoc inside individual mitmproxy hooks
- Preserve the current host-only behavior as the first completed execution slice: host-only policy loading and matching
  are now directly unit-testable before request-aware matcher work expands the surface area

## Acceptance Criteria

- [ ] Host-only rules still block at CONNECT when possible
- [ ] HTTPS requests for rule-bearing hosts are allowed or blocked at request time based on scheme, method, path, and
      query rules
- [ ] HTTP and HTTPS matching semantics are aligned for the same policy
- [ ] Block logs carry enough detail to diagnose why a request failed without opening packet traces
- [ ] Direct unit coverage exists for the current host-only policy-loading and host-matching behavior so later matcher
      work can refactor safely

## Applicable Learnings

- `iptables` as gatekeeper plus proxy as enforcer remains the core model. Keep proxy behavior explicit and reviewable.
- Security-sensitive policy rendering should keep one merge path; the addon should consume the rendered IR rather than
  inventing parallel parsing behavior.
- If every case is only tested end to end, the suite will be slow and fragile. Keep matcher logic unit-testable and
  reserve a smaller set of wiring tests for mitmproxy integration.
- Documentation artifacts belong in `docs/`, and task execution details should stay in the milestone task records.
- For `m14`, matching a URL rule means the endpoint is trusted with the full request. Header and body inspection remain
  out of scope, so the matcher should stay focused on host, scheme, method, path, and query only.

## Plan

### Files Involved

- `images/proxy/addons/enforcer.py` - thin addon runtime that loads rendered policy, delegates CONNECT and request
  decisions, and translates matcher decisions into mitmproxy responses and structured logs
- `images/proxy/addons/policy_matcher.py` - new pure-Python runtime model for host selection, CONNECT decisions,
  request matching, and exact-query normalization
- `images/proxy/tests/test_enforcer.py` - addon wiring tests for CONNECT and request blocking, logging, and runtime
  integration boundaries
- `images/proxy/tests/test_policy_matcher.py` - new matcher-focused unit tests for host precedence, CONNECT behavior,
  rule evaluation, and query semantics
- `images/proxy/tests/test_render_policy.py` - extend only if matcher work exposes an assumption that the renderer is
  not already pinning down
- `.github/workflows/proxy-tests.yml` - keep the proxy Python test workflow aligned with the broader suite as coverage
  expands

### Approach

The current addon refactor solved the first blocker: host-only loading and matching are now testable without a live
mitmproxy runtime. That is necessary, but it is not the `m14.2` design. The full task still needs one explicit runtime
matcher model and one clear precedence contract, or request-aware rules will become ambiguous.

The main design decisions for `m14.2` are:

1. **One host record participates per request.** The renderer already sorts records by specificity. The matcher should
   select the single most specific host record that matches the request host: exact host before wildcard host, then the
   longest wildcard suffix. It should not union rules across multiple matching host records, or a broad wildcard record
   could silently widen a narrower exact-host policy.
2. **Rules are allow-only ORs of ANDs.** Within the selected host record, each rule is one conjunction of constraints
   over `schemes`, optional `methods`, optional `path`, and optional `query`. The host record allows the request if any
   rule matches.
3. **CONNECT and request phases share one policy engine.** CONNECT should not maintain a separate interpretation of the
   policy. Instead, the matcher should expose a CONNECT-time decision API that answers one of three cases for HTTPS:
   block immediately, allow immediately because the host is fully trusted for HTTPS, or allow the tunnel so the
   decrypted request can be evaluated later.
4. **Request matching should stay narrow and explicit.** `m14.2` should implement only the rule dimensions already
   stabilized in `m14.1`: scheme, method, path exact or prefix, and exact query matching. Headers and bodies remain out
   of scope by decision record `005`.

#### Runtime Matcher Model

The recommended implementation shape is:

- Keep `enforcer.py` as the addon entrypoint and flow adapter.
- Introduce a pure-Python matcher module that compiles rendered host records into a runtime policy model once at
  startup.
- Make that runtime model own:
  - host record selection by specificity
  - CONNECT-time HTTPS decisions
  - shared request evaluation for HTTP and HTTPS
  - exact query normalization for comparisons
  - decision metadata that the addon can log without re-deriving why the policy matched or failed

This is stricter than keeping all logic inside the addon class, but it is the right tradeoff. The matcher is where the
future complexity lives, so that is what should be unit-testable.

#### Host Selection and Precedence

For any host:

- If no rendered host record matches, the request is blocked.
- If more than one rendered host record matches, only the most specific record participates.
- Specificity follows the rendered order contract from `m14.1`:
  - exact host before wildcard host
  - among wildcards, longest suffix first

That keeps the `m14.1` merge and sort behavior meaningful at runtime and avoids accidental widening from wildcard
overlap.

#### CONNECT-Time Behavior

For HTTPS `CONNECT`, the matcher should evaluate the chosen host record and classify it into one of these outcomes:

- `block`: no matching host record exists, or the chosen record has no rule that could ever allow HTTPS traffic
- `allow_connect_fast_path`: the chosen record contains an HTTPS-capable catch-all rule that does not depend on method,
  path, or query, so request-phase inspection is unnecessary for allow or deny
- `allow_connect_inspect_request`: the chosen record may allow some HTTPS requests but requires method, path, or query
  inspection before the final decision

This preserves the current security boundary while still letting request-aware HTTPS rules work. It also avoids a weak
fallback where all rule-bearing HTTPS hosts are blindly allowed after CONNECT.

#### Request Matching Semantics

HTTP and decrypted HTTPS requests should go through the same matcher path:

- `scheme` compares against rendered `schemes`
- `method`, when present on the rule, compares against the request method uppercased
- `path` matches against the request path without query string
- `query.exact` compares against a normalized query multimap:
  - pair ordering ignored
  - repeated values preserved by per-key value lists
  - per-key value lists sorted before comparison
  - `query.exact: {}` means the request must have no query params
  - omitted `query` means the rule does not constrain the query string

The matcher should parse the request path centrally instead of assuming that mitmproxy has already separated the query
for us. Local API inspection confirms `Request.path` can include the query string, so the runtime matcher should split
path and query deliberately.

#### Logging Shape

`m14.2` needs logs that explain *why* a request was allowed or blocked, not just that it happened. The plan is to have
the matcher return a structured decision object that gives the addon enough context to log:

- phase: `connect` or `request`
- action: `allowed` or `blocked`
- host and scheme
- method and path when a request exists
- matched host record
- reason code, for example:
  - `host_not_allowed`
  - `https_not_permitted`
  - `connect_fast_path`
  - `request_rule_matched`
  - `no_rule_matched`

The exact field names can still be refined during execution, but the plan should reject vague logging that forces later
debugging back into packet traces.

#### Test Strategy

Split coverage by concern:

- `test_policy_matcher.py` for pure runtime semantics:
  - exact vs wildcard host precedence
  - longest wildcard precedence
  - CONNECT blocking for no match and HTTP-only rules
  - CONNECT fast-path allow for unconditional HTTPS trust
  - CONNECT defer-to-request for rule-bearing HTTPS hosts
  - shared HTTP and HTTPS request matching
  - method normalization
  - path exact and prefix rules
  - exact query matching including empty query, pair-order independence, repeated keys, and scalar normalization
- `test_enforcer.py` for addon behavior:
  - mapping matcher decisions to 403 responses
  - ensuring HTTP requests are blocked in `request()`
  - ensuring HTTPS hosts that need request inspection are not prematurely blocked at CONNECT
  - verifying structured logs include the matcher reason
- Keep full mitmproxy integration minimal for this task. The unit seam is the primary regression defense.

### Implementation Steps

- [x] Create a testable host-policy loading and matching seam in the proxy addon
- [x] Add unit tests for host-record normalization, wildcard matching, and current HTTP or CONNECT blocking behavior
- [x] Run the proxy Python tests locally and confirm the workflow still covers the suite
- [ ] Introduce a pure runtime matcher module for rendered host-record policies and route addon decisions through it
- [ ] Implement single-record host selection and CONNECT classification for HTTPS
- [ ] Implement shared HTTP and HTTPS request-rule evaluation for scheme, method, path, and exact query matching
- [ ] Add matcher-focused unit tests for precedence, CONNECT semantics, and request evaluation
- [ ] Expand addon wiring tests to cover request-phase allow or block decisions and structured reasons
- [ ] Run the full proxy Python suite locally and verify no host-only regressions were introduced

### Open Questions

- Whether the structured decision log should include a sanitized query representation for debugging, or whether that is
  too noisy and should stay out until we see a concrete need. Current recommendation: omit full query payloads by
  default and log only the reason plus host, method, and path.
- Whether the request matcher should cache the CONNECT-time host selection in `flow.metadata` for HTTPS requests.
  Current recommendation: start without caching unless mitmproxy flow behavior makes recomputation awkward.

## Outcome

### Acceptance Verification

- [x] Host-only rules still block at CONNECT when possible through direct unit coverage in
      `images/proxy/tests/test_enforcer.py`
- [ ] HTTPS requests for rule-bearing hosts are allowed or blocked at request time based on scheme, method, path, and
      query rules
- [ ] HTTP and HTTPS matching semantics are aligned for the same policy
- [ ] Block logs carry enough detail to diagnose why a request failed without opening packet traces
- [x] Direct unit coverage exists for the current host-only policy-loading and host-matching behavior so later matcher
      work can refactor safely via `images/proxy/tests/test_enforcer.py`

### Learnings

- Keeping mitmproxy-specific response creation lazy lets the addon stay importable in plain Python test environments
  without adding a full mitmproxy dependency to the unit-test workflow.

### Follow-up Items

- Extend the test seam from host-only allowlist evaluation to full request-rule matching once the `m14.2` matcher
  semantics are implemented.
