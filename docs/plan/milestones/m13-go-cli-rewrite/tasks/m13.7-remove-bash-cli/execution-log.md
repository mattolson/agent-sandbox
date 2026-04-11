# Execution Log: m13.7 - Remove Bash CLI

## 2026-04-10 00:00 UTC - Go-only cleanup implemented

Removed the legacy `cli/` tree, deleted the Bash-only CI and parity workflows, removed the old CLI image build path from repo scripts, created `docs/cli.md` as the Go command reference, and updated current docs and repo guidance so `internal/embeddata/templates/` is now the only live template source tree.

Verification passed with `go test ./...`, `go run ./cmd/agentbox version`, `git diff --check`, and `BUILD_DIRTY=false ./scripts/build-release-artifacts.bash --version v0.13.0 --out-dir /tmp/agentbox-go-only-release-test`.

**Issue:** The biggest cleanup risk was not code compilation; it was leaving behind live workflow or docs references to deleted Bash-era paths such as `cli/tests`, `scripts/parity.bash`, `scripts/sync-go-templates.bash`, or `images/cli/Dockerfile`.
**Solution:** Remove the dead implementation and transition scripts first, then sweep all current repo guidance and workflow files for those path references before running Go-only verification.

**Decision:** Keep historical milestone and task documents mostly intact, but update the current `m13` milestone summary plus repo guidance files so contributors see the Go-only state by default.

**Learning:** Final cleanup work should delete transitional infrastructure in the same change as the docs rewrite. If you leave either half behind, the repo keeps teaching a state that no longer exists.
