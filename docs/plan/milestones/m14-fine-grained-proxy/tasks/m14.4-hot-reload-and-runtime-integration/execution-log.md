# Execution Log: m14.4 - Hot Reload And Runtime Integration

## 2026-04-18 - Drafted the task plan

Reviewed the `m14` milestone plan, the current `entrypoint.sh` / `enforcer.py` / `policy_matcher.py` / `render-policy`
surfaces, and decision record `005`. The enforcer already loads the policy from a rendered IR through
`PolicyMatcher.from_policy_data`, and the renderer's `render_policy()` module function is already side-effect-free
outside of `__main__`. Those two facts let `m14.4` avoid inventing a second pipeline: reload can be a narrow swap
around the existing `render-policy` + matcher boundary.

**Issue:** mitmproxy does not ship a SIGHUP hook, so signal handling must be wired explicitly via
`loop.add_signal_handler` in the `running()` addon hook.
**Solution:** Install the handler in `running()` and tear it down in `done()`. The handler schedules the actual reload
on the asyncio loop so file I/O and validation do not run inside the signal callback.

**Decision:** Import `render-policy` in-process via `SourceFileLoader` instead of spawning a subprocess. Keeps a
single merge path, avoids temp-file staging, and gives Python-level exceptions for structured error logs. Flagged as
Open Question #1 in case you want subprocess isolation instead.

**Decision:** Defer a dedicated `agentbox policy reload` CLI wrapper. The milestone plan treats the CLI surface as
"future" and `agentbox compose kill -s HUP proxy` already works today. Flagged as Open Question #2.

**Decision:** Reload rejection keeps the last known-good matcher and emits a structured rejection event via
`logger.event`. Do not fall back to allow-all or per-layer partial application; failure is atomic.
