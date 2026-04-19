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

- [x] Sending `SIGHUP` to the proxy reloads policy without a container restart
- [x] Existing healthy connections are not dropped solely because a reload happened
- [x] Invalid reloaded policy is rejected atomically and leaves the prior policy active
- [x] Reload still uses the proxy-side `render-policy` path rather than inventing a second merge implementation
- [x] Reload emits a structured success log carrying the new matcher shape (host-record count plus
      exact/wildcard split) and a structured rejection log carrying the error message
- [x] The reload path is unit-testable without sending real signals, so failures are covered by CI
- [x] `docs/policy/schema.md` (or a dedicated reload section) explains how to trigger reload today and flags that a
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

- [x] Confirm mitmproxy does not install its own SIGHUP handler; prototype `loop.add_signal_handler(SIGHUP, ...)` in
      a scratch addon and verify it fires without interfering with SIGINT/SIGTERM shutdown behavior
- [x] Refactor `enforcer.py` so `PolicyEnforcer` exposes a plain `reload()` method (sync or async) that renders and
      swaps, then add `running()` / `done()` hooks that wire the signal to that method
- [x] Add a small helper that imports `render-policy` via `SourceFileLoader` and caches the module so reloads do not
      re-load the script on every signal
- [x] Add structured success and rejection log events via `logger.event`
- [x] Guard concurrent reloads with an `asyncio.Lock` or equivalent so overlapping signals do not interleave renders
- [x] Add unit tests in `test_enforcer.py` for: successful reload swap, rejected reload keeps prior matcher, render
      failure (e.g. malformed layered file) logs rejection, lock prevents overlapping renders, `running()` installs
      and `done()` removes the signal handler
- [x] Update `docs/policy/schema.md` with a "Reloading policy" section describing the `docker compose kill -s HUP
      proxy` workflow, the structured log events, and the last-known-good guarantee
- [x] Add a troubleshooting note pointing at the rejection log message shape
- [x] Run `go test ./...` and `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p
      'test_*.py'`; confirm no regressions

### Open Questions

All four planning questions resolved with the drafted defaults on 2026-04-19:

1. **Import `render-policy` in-process via `SourceFileLoader`.** Single merge path, no temp-file staging, and Python
   exceptions flow directly into the structured rejection log.
2. **Defer `agentbox policy reload` CLI wrapper.** `agentbox compose kill -s HUP proxy` works today; a dedicated
   wrapper belongs in a later milestone once we know whether it should also handle multi-container or remote cases.
3. **Emit a single `reload` event with host-record counts on success.** Per-host enumeration stays a startup-only
   thing. A future diff mode can be added without changing the log contract.
4. **Use `asyncio.Lock` to coalesce concurrent signals.** A second SIGHUP during an in-flight reload waits for the
   first to finish and then re-runs with the latest on-disk state.

## Outcome

### Acceptance Verification

- [x] **SIGHUP reloads without restart** — `PolicyEnforcer.running()` installs the SIGHUP handler on the asyncio
      loop (`images/proxy/addons/enforcer.py`); `_handle_reload_signal` schedules `reload()`; `reload()` swaps the
      matcher in place. No container lifecycle change.
- [x] **Healthy connections not dropped** — reload mutates `self.matcher` only; it never calls mitmproxy shutdown
      helpers. Flow hooks read `self.matcher` per request, and existing CONNECT tunnels keep forwarding bytes.
- [x] **Invalid policy rejected atomically** — the new matcher is built fully before the swap. On exception the
      except branch emits a rejection event and returns without touching `self.matcher`. Covered by
      `PolicyEnforcerReloadTests.test_reload_keeps_prior_matcher_when_render_raises` and
      `test_reload_rejects_invalid_policy_and_keeps_prior_matcher`.
- [x] **Reuses `render-policy`** — `_render_matcher` loads `/usr/local/bin/render-policy` via `SourceFileLoader` and
      calls its `render_policy()` module function. No duplicate merge implementation.
- [x] **Structured success/failure logs** — `_reload_event("applied", ...)` emits `type=reload`, `action=applied`,
      `host_records`, `exact_host_count`, `wildcard_host_count`; `_reload_event("rejected", error=...)` emits the
      error message. Both bypass quiet mode via `JsonLogger.event(..., always=True)`. Covered by the applied/rejected
      tests and `test_reload_events_emit_even_in_quiet_mode`.
- [x] **Unit-testable without real signals** — `reload()` is an `async def` exposed on the enforcer and called
      directly from tests. `PolicyEnforcerReloadTests` covers the full matrix.
- [x] **Docs updated** — `docs/policy/schema.md` has a "Reloading Policy" section with the exact
      `agentbox compose kill -s HUP proxy` invocation plus applied/rejected JSON shapes.
      `docs/troubleshooting.md` has a "Policy reload rejected" entry pointing at the log line.

### Learnings

- **mitmproxy does not claim SIGHUP.** Only SIGINT/SIGTERM are wired in `mitmproxy/tools/main.py`. SIGHUP is free
  for addon use as long as we install through `loop.add_signal_handler` in `running()` and tear down in `done()`.
- **Semantic coalescing versus hard dedup.** A `/simplify` pass suggested dropping a SIGHUP that arrives while a
  reload is in flight to avoid unbounded task accumulation. That hardens memory but weakens semantics — the later
  edit on disk would be lost. The original `asyncio.ensure_future(self.reload())` + lock-inside-`reload()` pattern
  keeps "latest on-disk wins" without meaningful risk, because reloads drain in milliseconds and SIGHUP is a
  manual, rare operation. Prefer correctness over theoretical scale when the scale is unreachable.
- **Logger event bypass flag.** Adding `always=False` to `JsonLogger.event()` keeps the quiet-mode contract for
  request logging while letting lifecycle events (reload applied/rejected) always surface. Simpler than introducing
  a second logger.

### Follow-up Items

- CLI wrapper landed as `agentbox proxy reload` in a follow-up commit, rather than `agentbox policy reload`. The
  `proxy` group leaves room for future monitoring and realtime-policy commands that operate on the sidecar rather
  than the rendered policy surface.
