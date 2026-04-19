# Task: m14.4 - Hot Reload And Runtime Integration

## Summary

Allow policy edits to take effect in a running proxy via `SIGHUP` without dropping healthy connections or introducing a
second policy render path.

## Scope

- Add reload handling in the proxy runtime and enforcer
- Re-render and validate policy on signal before swapping matcher state
- Keep the last known-good policy active if reload fails
- Emit structured reload success and failure logs
- Document the human and future-CLI workflow for validating and reloading policy changes

## Acceptance Criteria

- [ ] Sending `SIGHUP` to the proxy reloads policy without a container restart
- [ ] Existing healthy connections are not dropped solely because a reload happened
- [ ] Invalid reloaded policy is rejected atomically and leaves the prior policy active
- [ ] Reload still uses the proxy-side `render-policy` path rather than inventing a second merge implementation
- [ ] Reload emits a structured success log carrying the new matcher shape (host-record count plus
      exact/wildcard split) and a structured rejection log carrying the error message
- [ ] The reload path is unit-testable without sending real signals, so failures are covered by CI
- [ ] `docs/policy/schema.md` (or a dedicated reload section) explains how to trigger reload today and flags that a
      future CLI wrapper is planned

## Applicable Learnings

- Security-sensitive policy rendering should keep one merge path. Reload must reuse `images/proxy/render-policy` rather
  than open-coding a second normalization pipeline. (from m14.1 plan)
- The `m14.2` matcher boundary is a first-class swap point: `PolicyMatcher.from_policy_data` already accepts an
  in-memory dict, so reload can build a fresh matcher without temp files.
- For proxy addons that block before the response hook runs, storing the policy decision on the flow avoids response
  logging relabeling blocked requests as allowed. Reload must not invalidate decisions already attached to in-flight
  flows. (from `docs/plan/learnings.md`)
- Loading `render-policy` from another Python module requires `SourceFileLoader` because it has no `.py` suffix; the
  tests already use this pattern and the enforcer can reuse it. (from m14.3 execution log)
- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs. System Python lacks `yaml`.

## Plan

### Files Involved

- `images/proxy/addons/enforcer.py` — add a `reload()` method, `running()` / `done()` lifecycle hooks that install and
  tear down the SIGHUP handler, last-known-good fallback, and structured reload log events.
- `images/proxy/addons/policy_matcher.py` — already exposes `from_policy_data`; likely no change, but may need a helper
  that also reports the matcher shape for the success log.
- `images/proxy/render-policy` — keep `render_policy()` callable as a module function (today it already is, guarded by
  `__name__ == "__main__"`), and make sure importing it has no side effects beyond module initialization.
- `images/proxy/entrypoint.sh` — no functional change, but worth double-checking that the initial render path still
  agrees with the runtime reload path.
- `images/proxy/tests/test_enforcer.py` — add reload coverage: happy path swap, rejection of invalid policy with
  last-known-good preservation, render-policy raising an exception, signal-handler lifecycle.
- `docs/policy/schema.md` — document the reload workflow and its guarantees.
- `docs/troubleshooting.md` — brief pointer for "reload failed, check proxy logs."

### Approach

The reload surface sits entirely inside the proxy image. The Go CLI does not need new commands in `m14.4`; users can
reach the proxy today with `docker compose kill -s HUP proxy` via the existing `agentbox compose` passthrough.

The core idea is a narrow reload entry point on the enforcer:

1. **Matcher swap is the atomic boundary.** Build a new `PolicyMatcher` before touching `self.matcher`. If anything
   raises, log the rejection and leave `self.matcher` pointing at the previous instance. Python's GIL makes reference
   assignment atomic, and every flow hook reads `self.matcher` at most once per request, so concurrent traffic does
   not see a half-updated matcher.
2. **Reuse `render-policy`.** The addon imports `render-policy` via `SourceFileLoader` (same pattern the proxy tests
   already use) and calls `render_policy()` to produce the rendered dict. That dict goes straight into
   `PolicyMatcher.from_policy_data`, which preserves the existing validation story. This satisfies the "reuse
   proxy-side render path" requirement without adding a subprocess hop.
3. **Signal handling through asyncio.** mitmproxy runs its addon hooks on a single asyncio loop. The `running()` hook
   is the right place to call `loop.add_signal_handler(signal.SIGHUP, self._handle_reload_signal)`; `done()` is the
   right place to `remove_signal_handler(signal.SIGHUP)`. The signal callback schedules the actual reload work on the
   loop so the render subprocess / file I/O does not block the handler directly.
4. **Last-known-good fallback.** On reload failure, emit a rejection log with the error message and leave the
   previous matcher installed. No partial updates. Never let reload weaken the policy to allow-all.
5. **Structured logs.** Extend `JsonLogger` usage to emit reload events:
   - Success: `{"ts", "type": "reload", "action": "applied", "host_records": N, "exact_host_count": X,
     "wildcard_host_count": Y}`
   - Rejection: `{"ts", "type": "reload", "action": "rejected", "error": "<message>"}`
   The existing `logger.info` path is for narrative strings; reload events belong in `logger.event` so they are
   machine-parseable alongside request logs.
6. **In-flight requests.** Existing CONNECT tunnels keep forwarding encrypted bytes; reload takes effect on the next
   request that reaches the matcher. Reload never calls mitmproxy shutdown or flow teardown helpers, so healthy
   connections continue uninterrupted.
7. **Concurrent signals.** A second SIGHUP that arrives while a reload is still in flight should be coalesced: drop
   the second signal or schedule exactly one follow-up reload. This avoids stacking renders when a user mashes the
   reload command. A simple `asyncio.Lock` on the reload coroutine is enough.

### Implementation Steps

- [ ] Confirm mitmproxy does not install its own SIGHUP handler; prototype `loop.add_signal_handler(SIGHUP, ...)` in
      a scratch addon and verify it fires without interfering with SIGINT/SIGTERM shutdown behavior
- [ ] Refactor `enforcer.py` so `PolicyEnforcer` exposes a plain `reload()` method (sync or async) that renders and
      swaps, then add `running()` / `done()` hooks that wire the signal to that method
- [ ] Add a small helper that imports `render-policy` via `SourceFileLoader` and caches the module so reloads do not
      re-load the script on every signal
- [ ] Add structured success and rejection log events via `logger.event`
- [ ] Guard concurrent reloads with an `asyncio.Lock` or equivalent so overlapping signals do not interleave renders
- [ ] Add unit tests in `test_enforcer.py` for: successful reload swap, rejected reload keeps prior matcher, render
      failure (e.g. malformed layered file) logs rejection, lock prevents overlapping renders, `running()` installs
      and `done()` removes the signal handler
- [ ] Update `docs/policy/schema.md` with a "Reloading policy" section describing the `docker compose kill -s HUP
      proxy` workflow, the structured log events, and the last-known-good guarantee
- [ ] Add a troubleshooting note pointing at the rejection log message shape
- [ ] Run `go test ./...` and `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p
      'test_*.py'`; confirm no regressions

### Open Questions

1. **Import render-policy vs spawn a subprocess?** The plan above imports `render-policy` inline. The alternative is
   `subprocess.run(["/usr/local/bin/render-policy", "--output", path])` matching `entrypoint.sh`. Import is faster,
   avoids temp files, and gives us structured exceptions instead of parsing stderr. Subprocess is better isolated but
   duplicates the entrypoint's behavior. Default: import. Flag if you want to force subprocess instead.

2. **Should we add `agentbox policy reload` in `m14.4`?** The milestone plan says "document the human and
   future-CLI workflow," which reads as "CLI comes later." Default: document `docker compose kill -s HUP proxy`
   (exposed today through `agentbox compose`) and defer a dedicated CLI command. If you want the CLI command in this
   task, we'd add a thin wrapper in `internal/cli/policy.go` that calls `docker compose kill -s HUP proxy`.

3. **What exactly goes in the success log?** Current enforcer logs `Adding '<host>' to allowlist` at startup per host
   record, which would be noisy if repeated on every reload. Default: on reload success, skip per-host enumeration
   and emit a single `reload` event with counts. Flag if you want per-host diffs (added/removed) — that's richer but
   adds comparison logic.

4. **Concurrency model.** Default: a single `asyncio.Lock` guards `reload()`. If two SIGHUPs arrive in quick
   succession the second waits for the first to finish and then runs once more with the latest on-disk state. An
   alternative is "drop the second signal entirely." Locking is marginally more code but guarantees the final reload
   reflects the latest policy content.

5. **Does reload need to signal the enforcer into a degraded state while in-flight?** No — because the swap is
   atomic, requests either see the old matcher fully or the new matcher fully. We explicitly do not pause traffic
   during reload.

## Outcome

### Acceptance Verification

Pending execution.

### Learnings

Pending execution.

### Follow-up Items

Pending execution.
