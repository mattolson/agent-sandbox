# Execution Log: m14.2 - Request-Phase Enforcement

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
