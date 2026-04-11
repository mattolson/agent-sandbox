# Task: m13.7 - Remove Bash CLI

## Summary

Remove the legacy Bash `agentbox` implementation, its parity and CI scaffolding, the old Docker CLI image distribution path, and the remaining docs that still treat those surfaces as live.

## Scope

- Delete the legacy `cli/` implementation tree and its Bash-specific tests/support files
- Remove the Bash-vs-Go parity harness and the shell-specific CI workflows that existed only to keep the old CLI alive during transition
- Remove the old Docker CLI image build path from repo scripts and GitHub Actions
- Promote `internal/embeddata/templates/` to the only live template source tree
- Move the command reference to `docs/cli.md` and update user/developer docs accordingly
- Update milestone/project docs so `m13` reflects the post-cutover Go-only state

## Acceptance Criteria

- [x] The repo no longer contains the legacy Bash `agentbox` implementation or the old CLI image build path
- [x] `go test ./...` passes without template-sync or parity prerequisites
- [x] The release artifact helper still works after removing the sync/parity plumbing
- [x] README, CLI reference, contributor docs, and agent instructions no longer point at `cli/` as a live surface
- [x] Embedded templates are treated as the only live template source tree in code, tests, and contributor guidance

## Applicable Learnings

- The Bash CLI and parity suite were useful transition tools, but once the Go cutover shipped they became maintenance liabilities rather than safety nets.
- Stable release automation should depend on the shipped Go code and embedded assets only; tying it to deleted legacy scaffolding is an avoidable failure mode.
- Keeping the template source of truth inside the codebase that actually ships is simpler than synchronizing from a legacy tree that no longer serves users.

## Plan

### Files Involved

- `cli/**` - delete the retired Bash CLI implementation, tests, templates, and vendored BATS support
- `.github/workflows/cli-tests.yml` and `.github/workflows/parity-tests.yml` - delete obsolete Bash-era workflows
- `.github/workflows/go-tests.yml` and `.github/workflows/release-go-binaries.yml` - remove sync/parity assumptions
- `.github/workflows/build-images.yml` and `images/build.sh` - remove the `agent-sandbox-cli` image build path
- `images/cli/**` - delete the retired CLI image Dockerfile
- `scripts/parity.bash` and `scripts/sync-go-templates.bash` - delete obsolete transition scripts
- `internal/embeddata/embeddata.go` and `internal/scaffold/templates_test.go` - remove template-sync assumptions and keep tests focused on embedded templates
- `README.md`, `docs/cli.md`, `docs/troubleshooting.md`, `docs/policy/schema.md`, `docs/roadmap.md`, `AGENTS.md`, `CONTRIBUTING.md`, and `.agents/skills/add-agent/SKILL.md` - rewrite current docs and repo guidance for the Go-only state
- `docs/plan/project.md`, `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, and `docs/plan/learnings.md` - record the final cleanup and the resulting learnings

### Approach

Treat this as the post-cutover cleanup that removes temporary transition scaffolding. The Go CLI already owns the shipping path, so the remaining work is to delete the old implementation and then prune every workflow, script, and doc path that existed only to support that coexistence period. Anything still needed by the Go CLI must stay under `cmd/`, `internal/`, `scripts/build-release-artifacts.bash`, or the embedded template tree.

### Implementation Steps

- [x] Delete the legacy `cli/` tree, parity script, template-sync script, Bash-only workflows, and the retired CLI image Dockerfile
- [x] Remove old CLI image and parity references from build scripts and release workflows
- [x] Create `docs/cli.md` and update current docs and repo guidance to use it instead of `cli/README.md`
- [x] Promote `internal/embeddata/templates/` to the only live template source tree in code, tests, and guidance
- [x] Run Go-only verification and release-helper verification after the cleanup

### Open Questions

None after execution.

## Outcome

Removed the legacy Bash CLI, its parity and transition scaffolding, and the retired Docker CLI image build path. The repo is now Go-only: current docs point to the GitHub Releases binary plus `docs/cli.md`, workflows no longer depend on Bash parity or template sync, and embedded templates are the only live template source tree.

### Acceptance Verification

- [x] The repo no longer contains the legacy Bash `agentbox` implementation or the old CLI image build path.
  Verified by removing `cli/**`, `images/cli/**`, parity/sync scripts, and the related workflow/build-script references.
- [x] `go test ./...` passes without template-sync or parity prerequisites.
  Verified locally.
- [x] The release artifact helper still works after removing the sync/parity plumbing.
  Verified with `BUILD_DIRTY=false ./scripts/build-release-artifacts.bash --version v0.13.0 --out-dir /tmp/agentbox-go-only-release-test`.
- [x] README, CLI reference, contributor docs, and agent instructions no longer point at `cli/` as a live surface.
  Verified in `README.md`, `docs/cli.md`, `docs/troubleshooting.md`, `docs/policy/schema.md`, `AGENTS.md`, `CONTRIBUTING.md`, and `.agents/skills/add-agent/SKILL.md`.
- [x] Embedded templates are treated as the only live template source tree in code, tests, and contributor guidance.
  Verified in `internal/embeddata/embeddata.go`, `internal/scaffold/templates_test.go`, `docs/policy/schema.md`, and `AGENTS.md`.

### Learnings

- Once the cutover is real, keeping the legacy implementation around “just in case” quickly turns into duplicated docs, workflows, and asset pipelines rather than meaningful safety.
- Template sync layers are useful during migration, but the clean end state is one live template tree owned by the shipped implementation.

### Follow-up Items

- Consider a smaller follow-up to trim historical planning docs that still mention the old Bash transition paths in narrative examples.
