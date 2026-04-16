# Execution Log: m14.2 - Request-Phase Enforcement

## 2026-04-16 00:10 UTC - Confirmed m14.2 is complete after follow-up verification

Reviewed the finished task record and the implemented matcher runtime. `m14.2` is complete: the request-phase matcher,
CONNECT classification, shared HTTP and HTTPS rule evaluation, structured decision logging, and direct unit coverage
all landed and the task acceptance criteria are satisfied.

**Decision:** Treat later follow-up changes such as wiring the proxy Python suite into `make test` and excluding proxy
tests from the image build context as post-task maintenance, not additional `m14.2` scope.

**Rationale:** Those changes improve repo workflow and image hygiene, but they do not change the request-phase
enforcement behavior defined by this task.

**Verification:** `make test` now passes, including both `go test ./...` and the proxy Python suite.

## 2026-04-15 06:32 UTC - Request-phase matcher landed and proxy Python suite passed

Implemented the pure runtime matcher in `images/proxy/addons/policy_matcher.py`, rewired `enforcer.py` to delegate
CONNECT and request decisions through it, expanded the addon wiring tests, and added matcher-focused unit coverage for
host precedence, CONNECT classification, shared HTTP and HTTPS evaluation, path parsing, and exact query semantics.

**Decision:** Keep policy interpretation in the matcher module and keep `enforcer.py` focused on mitmproxy flow wiring,
structured logs, and response creation.

**Rationale:** This preserves one testable policy engine while avoiding duplicated CONNECT and request logic in the
addon hooks.

**Issue:** Direct file-loader tests for the new dataclass-based matcher failed because `exec_module` was not inserting
the module into `sys.modules`, which `dataclasses` expects during class creation.

**Solution:** Updated the direct-loader test helpers to register the module in `sys.modules` before calling
`exec_module`.

**Decision:** Do not log full query payloads in structured decision logs for `m14.2`.

**Rationale:** The reason, host, scheme, method, path, and matched host are enough to explain allow or block outcomes
for the current rule surface, and full query logging would add noise and potentially widen log exposure without a clear
need.

**Verification:** `/opt/proxy-python/bin/python -m unittest discover -s images/proxy/tests -v` passed with 28 tests.

## 2026-04-14 06:12 UTC - Expanded m14.2 into a full implementation plan and paused for approval

Revisited the milestone plan, the `m14.1` rendered-policy contract, decision record `005`, and the freshly refactored
addon seam. Reworked the `m14.2` task document from a narrow execution slice into a full implementation plan that now
covers host-record precedence, CONNECT versus request-phase behavior, matcher boundaries, logging expectations, and the
unit-test strategy.

**Decision:** At runtime, only the single most specific matching host record should participate in enforcement.

**Rationale:** The renderer already sorts host records by specificity. Unioning rules across multiple matching records
would let broad wildcard entries silently widen narrower exact-host policy.

**Decision:** HTTPS CONNECT evaluation should be a three-way classification: block immediately, allow immediately via a
fast path, or allow the tunnel so the decrypted request can be evaluated later.

**Rationale:** This preserves the current host-only CONNECT fast path without weakening the policy for HTTPS hosts that
need method, path, or query inspection.

**Decision:** Keep the runtime matcher pure and unit-testable in a dedicated module instead of continuing to grow the
addon class as the primary policy engine.

**Rationale:** `m14.2` is where policy complexity starts to matter. The matcher needs direct tests for semantics and
precedence without depending on mitmproxy flow wiring.

## 2026-04-14 05:52 UTC - Host-only refactor landed with direct addon unit coverage

Refactored `images/proxy/addons/enforcer.py` so host-only policy parsing, host-record normalization, wildcard matching,
JSON logging, and response creation can be exercised without a live mitmproxy runtime. Added
`images/proxy/tests/test_enforcer.py` to cover the current host-only invariants and renamed the workflow step in
`proxy-tests.yml` so it reflects the broader Python suite.

**Decision:** Keep the addon in one file for now, but separate the policy and logging concerns behind explicit classes
instead of immediately splitting modules.

**Rationale:** This keeps the runtime wiring simple during the first `m14.2` slice while still giving the upcoming
request-aware matcher work a direct unit-test seam.

**Decision:** Make mitmproxy response creation lazy and allow the module to import without mitmproxy installed.

**Rationale:** The CI workflow only needs `PyYAML` for the current unit tests, and the host-only behavior can now be
tested without dragging the full mitmproxy runtime into the unit-test dependency set.

**Verification:** `/opt/proxy-python/bin/python -m unittest discover -s images/proxy/tests -v` passed with 15 tests.

## 2026-04-14 05:40 UTC - Started with host-only addon refactor and unit-test groundwork

Reviewed the `m14` milestone plan, `m14.1` output, the proxy learnings, and the current addon implementation. The
addon is still a single class that combines environment handling, rendered-policy loading, host-record normalization,
wildcard matching, logging, and mitmproxy hooks.

**Decision:** Start `m14.2` by separating the host-only policy-loading and matching behavior behind a direct unit-test
seam before adding request-aware rule evaluation.

**Rationale:** The current host-only path is security-sensitive and is about to become more complex. Without a direct
unit seam, later `m14.2` changes would force either brittle end-to-end tests or unsafe refactors.
