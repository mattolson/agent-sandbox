# Execution Log: m8.7 - Restart Running Services On Agent Switch

## 2026-03-15 02:56 UTC - Implemented switch-time runtime reconciliation

Reviewed the `m8` milestone and the existing `switch`, `edit compose`, and `run-compose` flows to align this change with the established layered compose wrapper instead of adding a parallel compose path.

**Decision:** Probe running containers before changing the active agent, then run `down` and `up -d` after writing the new active-agent state so the restarted stack uses the selected agent's compose layer.

**Issue:** The existing switch suite encoded the older `m8.1` behavior that Docker must never be touched during an agent change, which directly conflicted with the current milestone expectation and the user-reported inconsistency.
**Solution:** Replaced that stale assertion with explicit tests for both branches: running stacks restart, stopped stacks do not.

**Learning:** Runtime side effects in control-plane commands need tests that reflect the final milestone behavior, not just the earliest incremental slice that first introduced the command.
