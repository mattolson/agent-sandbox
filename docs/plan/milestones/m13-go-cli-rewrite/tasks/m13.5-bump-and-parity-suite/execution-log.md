# Execution Log: m13.5 - Bump And Parity Suite

## 2026-04-04 05:18 UTC - Bump port and parity workflow implemented

Replaced the final Go CLI placeholder with a real `bump` command in `internal/cli/bump.go`, added native compose service-image helpers in `internal/scaffold/compose.go`, added shared image helpers in `internal/docker/images.go`, extended runtime coverage with `internal/runtime/lifecycle_test.go`, and created a dedicated parity layer with `scripts/parity.bash`, fixture repos under `testdata/parity/`, and `.github/workflows/parity-tests.yml`. Verification passed with `go test ./...`, `go build ./cmd/agentbox`, `cli/run-tests.bash test/bump/`, and the new parity harness.

**Issue:** The first parity-harness pass produced false failures in the edit-policy comparison even though the Go implementation matched the intended behavior. The real incompatibilities were in the oracle plumbing: Bash `open_editor` insists on `/dev/tty`, and its edit commands use second-resolution mtimes to decide whether a file changed.
**Solution:** Wrap Bash `edit` parity cases in a pseudo-tty via `script -qec`, normalize combined console output instead of assuming stderr-only logs, and add an intentional one-second editor delay before modifying files so both CLIs observe a real change event.

**Decision:** Keep the parity suite as a dedicated workflow rather than folding it into the existing Go workflow. That preserves the explicit three-layer transition model and makes parity regressions easier to distinguish from ordinary Go unit-test failures.

**Learning:** Parity harnesses need to model the Bash CLI's environment, not just its command-line arguments. TTY assumptions, mtime resolution, and shared external-tool behavior all affect whether a comparison is measuring product drift or just harness mismatch.

## 2026-04-04 04:12 UTC - Planning complete

Reviewed the `m13.5` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, current learnings, decision `004`, the completed `m13.2` through `m13.4` task artifacts, the remaining `bump` placeholder in `internal/cli/root.go`, the reusable image pinning helper in `internal/docker/images.go`, the compose read/write helpers in `internal/scaffold/compose.go`, the Bash `bump` implementation in `cli/libexec/bump/bump`, its BATS coverage in `cli/test/bump/*.bats`, and the current CI split between `.github/workflows/go-tests.yml` and `.github/workflows/cli-tests.yml`. I also confirmed that the planned `testdata/parity/` fixtures and `scripts/parity.bash` harness do not exist yet.

The main planning conclusion is that `m13.5` should keep `bump` thin by reusing the existing Docker pinning helper and extending the native compose mutator layer, then add a dedicated parity harness that runs both CLIs against the same temp fixtures with semantic assertions rather than brittle raw file comparisons.

**Issue:** The repo currently has only two verification layers during the rewrite: Bash BATS and Go unit tests. That leaves a gap where both implementations can pass their own tests while still drifting apart on user-visible behavior.
**Solution:** Plan `m13.5` around a third verification layer: a parity harness with shared fixtures, stubbed external tools, and command-by-command semantic comparisons between `cli/bin/agentbox` and the Go CLI.

**Decision:** Recommend a dedicated parity workflow rather than hiding the comparison suite inside the existing Go workflow. That keeps the transition state explicit: Bash oracle, Go implementation, and Bash-vs-Go parity all remain separately visible in CI.

**Learning:** The remaining rewrite work is not just one command. `bump` is the last missing user-facing behavior, but the more important release blocker is proving that future changes cannot silently drift away from the Bash oracle once the Go binary becomes the default path.
