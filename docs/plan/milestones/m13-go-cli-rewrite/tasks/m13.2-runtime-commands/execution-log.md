# Execution Log: m13.2 - Runtime Commands

## 2026-04-01 04:53 UTC - Runtime commands implemented and verified

Implemented Go runtime layout resolution in `internal/runtime/compose.go`, legacy-layout upgrade guidance in `internal/runtime/legacy.go`, testable streamed/captured Docker execution in `internal/docker/invocation.go`, and real Cobra handlers for `compose`, `up`, `down`, `logs`, `exec`, `policy config`, and `policy render` in `internal/cli/runtime_commands.go` plus `internal/cli/policy.go`. Added command-level and runtime-level Go tests covering compose file ordering, mutating-command sync predicates, `exec` startup behavior, proxy-side policy rendering, and legacy-layout failures.

**Issue:** The Bash implementation refreshes some managed runtime files before mutating compose operations, but reproducing that entire path here would have pulled a lot of scaffold-generation logic from `m13.3` into this task.
**Solution:** Keep runtime sync as an injectable seam in the Go command layer and verify the mutating-command decision points now, while leaving the default implementation minimal until the broader scaffold port lands.

**Decision:** Treat the m13.2 parity bar as compose file resolution, subprocess invocation shape, and user-facing guardrails rather than forcing a premature rewrite of all managed-file refresh behavior.

**Learning:** An injectable Docker runner plus temp-repo fixtures gives good parity coverage for runtime commands without needing a live Docker daemon in the unit test layer.

## 2026-04-01 03:30 UTC - Planning complete

Reviewed the `m13.2` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, `docs/plan/learnings.md`, decision `004`, the completed `m13.1` task artifacts, and the current Bash runtime command implementation in `cli/lib/run-compose`, `cli/lib/cli-compose.bash`, `cli/lib/devcontainer.bash`, `cli/lib/legacy-layout.bash`, `cli/libexec/compose/*`, `cli/libexec/up/*`, `cli/libexec/down/*`, `cli/libexec/logs/*`, `cli/libexec/exec/exec`, and `cli/libexec/policy/{config,render}` together with the matching BATS coverage in `cli/test/compose/run-compose.bats`, `cli/test/compose/compose.bats`, `cli/test/exec/exec.bats`, `cli/test/policy/render.bats`, and `cli/test/path/find_compose_file.bats`.

The main planning conclusion is that `m13.2` should port runtime layout resolution, compose file ordering, legacy-layout guardrails, `docker compose` passthrough, `exec` startup behavior, and proxy-side `policy config` rendering into reusable Go packages without widening early into a full init/scaffolding rewrite.

**Issue:** The Bash runtime commands refresh some managed files before mutating compose operations, but those refresh paths are intertwined with scaffold-generation logic that milestone `m13.3` is expected to port more fully.
**Solution:** Plan `m13.2` around shared runtime discovery and Docker/Compose invocation first, and only add the smallest Go runtime-sync hook needed to preserve runtime-command semantics for already-initialized projects if tests prove it is necessary.

**Decision:** Use the current Bash runtime commands and BATS tests as the parity spec for compose file ordering, `exec` behavior, `policy config`, and legacy-layout errors instead of inferring behavior from milestone text alone.

**Learning:** The critical design seam for `m13.2` is not the Cobra wiring; it is the reusable runtime-layout resolver that decides CLI versus centralized devcontainer mode, emits compose layers in the correct order, and keeps legacy-layout guardrails user-facing.
