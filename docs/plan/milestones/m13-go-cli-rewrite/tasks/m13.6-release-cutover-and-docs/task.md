# Task: m13.6 - Release Cutover And Docs

## Summary

Make the Go binary the supported distribution path and update project docs, CI, and release automation to match.

## Scope

- Add build and release automation for macOS and Linux Go binaries (`amd64`, `arm64`)
- Publish versioned GitHub release archives plus checksums for the supported platforms
- Update installation and upgrade docs to use direct binary downloads from GitHub Releases as the primary install path instead of the Docker CLI image and host `yq`
- Keep the Docker CLI image path as a clearly deprecated fallback during the transition instead of removing it immediately
- Switch the repo's primary `agentbox` implementation path to the Go binary once parity gates are already in place
- Clean up obsolete Bash-only distribution guidance after the first Go release path is validated, without removing the Bash oracle needed by parity
- Explicitly defer Homebrew packaging and installer-script automation to fast-follow work after the binary release path is stable

## Acceptance Criteria

- [ ] A tagged release produces downloadable archives and checksums for all supported platforms and architectures
- [ ] README, `cli/README.md`, troubleshooting docs, and changelog document manual binary install from GitHub Releases as the primary path and no longer instruct users to install `yq`
- [ ] The Go binary can manage a project end-to-end using the documented install flow
- [ ] The Docker CLI image path remains available only as a clearly deprecated fallback during the transition
- [ ] Homebrew and installer-script work are called out as fast-follow, not hidden inside m13 scope

## Applicable Learnings

- The Bash CLI and its tests are still the best behavioral oracle, so cutover should change distribution and documentation first, not remove the Bash implementation or parity workflow prematurely.
- Native YAML and JSON handling are already in place in the Go CLI, so user-facing install docs should stop teaching a host-side `yq` prerequisite once the Go binary becomes primary.
- Strong ownership boundaries matter more than matching one exact YAML byte shape; release verification should use end-to-end CLI behavior over the documented install flow, not just artifact creation.
- The parity workflow is now a dedicated third CI layer. `m13.6` should keep that visible until at least one successful Go-first release has shipped and the fallback story has been exercised.
- Documentation cutovers fail when they leave old install paths half-alive. If README, CLI docs, troubleshooting, roadmap, and changelog disagree, users will keep following the stale Bash or Docker image guidance.
- The repo already has version metadata support via `internal/version` and existing GitHub Actions patterns for image publishing, so release work should reuse those seams instead of inventing a second metadata story.

## Plan

### Files Involved

- `.github/workflows/release-go-binaries.yml` - new workflow to build, archive, checksum, and publish Go release assets for macOS and Linux on version tags
- `.github/workflows/go-tests.yml` and/or `.github/workflows/parity-tests.yml` - adjust triggers or references only if needed so the release path clearly depends on the existing parity gates rather than bypassing them
- `.github/workflows/build-images.yml` - keep the Docker CLI image path available, but update any release-facing naming or summary text if needed so it is clearly a deprecated fallback rather than the primary distribution artifact
- `cmd/agentbox/main.go` and `internal/version/version.go` - verify or minimally extend release-time version stamping via `-ldflags` so downloaded binaries report a stable release version, commit, timestamp, and dirty state source
- `scripts/build-release-artifacts.bash` or similar helper - optional shared packaging logic for archive naming, checksum generation, and local smoke verification if the workflow becomes too large to keep inline
- `README.md` - replace clone-`cli/bin` and `yq` install guidance with GitHub Releases binary install instructions, plus the deprecated Docker-image fallback note
- `cli/README.md` - rewrite the top-level framing so this document describes the command surface and legacy Bash/developer context, while pointing end users to the Go binary install path
- `docs/troubleshooting.md` - update the Docker CLI image section so it is explicitly a deprecated fallback and add any binary-install troubleshooting that becomes necessary during execution
- `CHANGELOG.md` - add an unreleased or release entry documenting the Go-binary cutover, removal of documented host `yq` dependency, and deprecated Docker CLI fallback
- `docs/roadmap.md` - update the m13 summary so it reflects Go binary distribution as the primary path rather than the old Docker CLI image
- `images/cli/Dockerfile` - only if the fallback image needs a minimal update to wrap or invoke the Go binary instead of the Bash tree; avoid broad image churn unless required by the chosen fallback design
- `docs/plan/milestones/m13-go-cli-rewrite/tasks/m13.6-release-cutover-and-docs/*.md` - living task plan and execution log

### Approach

Treat `m13.6` as a release-path cutover, not as a packaging free-for-all. The key deliverable is a repeatable GitHub release flow that emits archives and checksums for the supported OS/architecture matrix and produces binaries with explicit version metadata via `-ldflags`. The repo already has the needed ingredients: a working Go CLI, existing CI gates (`go-tests`, Bash tests, parity), and a version package that accepts release-time metadata. The task should connect those pieces with the smallest possible amount of new release plumbing.

Use a dedicated Go-binary release workflow rather than overloading `build-images.yml`. The image workflow is already long and organized around GHCR publishing, while `m13.6` needs a different artifact model: zipped or tarred binaries plus a checksum file attached to a GitHub release. A separate workflow keeps the boundary clear: one pipeline publishes runtime images, another publishes the primary host install artifact. That also makes the deprecation story honest. The Docker CLI image can continue to exist during the transition, but it should stop looking like the main thing we ship.

Prefer plain GitHub Actions plus a small repo-owned packaging script over introducing GoReleaser in this task. GoReleaser would solve the mechanics, but it would also add a substantial new config surface right at cutover time. This repo already leans on explicit shell and workflow scripts for build logic, and the required artifact matrix is narrow. Unless implementation proves unexpectedly awkward, a small packaging helper plus a focused workflow is the lower-risk option. If that assumption turns out wrong during execution, capture the tradeoff explicitly before adding a new release tool.

The release workflow should build `agentbox` for `darwin/amd64`, `darwin/arm64`, `linux/amd64`, and `linux/arm64`, stamp each binary with version metadata derived from the tag and commit, archive them under a stable naming convention, generate a checksum manifest, and upload the assets to the tagged GitHub release. It should also run a minimal smoke check on each built binary, at least `agentbox version`, before publishing. It does not need to rerun the entire parity suite if the branch protections already require that before merge, but it should not create a path where a maintainer can publish a tag from an unvalidated commit without noticing.

For documentation, change the default narrative everywhere that currently points users to the Bash checkout or Docker CLI image. README should show direct binary download and PATH setup as the recommended path, remove the host `yq` prerequisite, and move the Docker image to a clearly marked fallback subsection with its tradeoffs. `cli/README.md` should stop reading like the primary install guide and instead become a command reference plus maintenance note for the legacy Bash path that still exists for parity and fallback. `docs/troubleshooting.md` should be updated to reflect that the Docker CLI image is now exceptional rather than normal. `CHANGELOG.md` and `docs/roadmap.md` should make the cutover explicit so the repo history and roadmap do not keep advertising the old distribution model.

Be careful about what "clean up Bash-only distribution plumbing" means. The wrong interpretation is deleting `cli/`, `cli-tests.yml`, or the parity harness as soon as the first binary workflow lands. The right interpretation is removing Bash-first install guidance and any release-path machinery that makes the Bash or Docker image look like the primary user distribution. Keep the Bash implementation in-repo as the oracle until a released Go-first path has been validated in practice. The Docker CLI image should remain buildable and documented only as a deprecated fallback until a later task deliberately removes it.

### Implementation Steps

- [ ] Confirm the release artifact contract: file naming, archive format, checksum format, tag pattern, and whether release upload attaches to pre-created GitHub releases or creates them directly from the workflow
- [ ] Add a dedicated Go-binary release workflow, plus a small packaging helper script if that materially reduces duplication across matrix jobs
- [ ] Wire release-time version stamping through `-ldflags` and add or extend tests/smoke checks so downloaded binaries report stable release metadata
- [ ] Add release verification that exercises the built binary through at least `agentbox version` and one documented install-flow smoke path
- [ ] Rewrite README install guidance around GitHub Releases binaries, remove documented host `yq` dependency, and move the Docker CLI image to an explicitly deprecated fallback section
- [ ] Update `cli/README.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, and `docs/roadmap.md` so they all reflect the same Go-first distribution story and the same fast-follow deferrals
- [ ] Decide whether the deprecated Docker CLI image should stay Bash-backed temporarily or should wrap the Go binary; implement only the minimum change needed to keep the fallback honest and working
- [ ] Verify the release workflow in a non-destructive way if possible, then run `go test ./...`, `go build ./cmd/agentbox`, and a local binary-install smoke test that follows the updated docs

### Open Questions

- Should the release workflow trigger on tag push, on `release.published`, or as a two-step flow where one event creates the release shell and the other uploads assets? The choice affects how easy it is to recover from failed uploads without retagging.
- Do we want the deprecated Docker CLI fallback to continue shipping the Bash tree for one transition release, or should `images/cli/Dockerfile` pivot immediately to running the Go binary inside the image so fallback users also exercise the new codepath?
- Is a dedicated upgrade note needed for users currently relying on `cli/bin/agentbox` in PATH, or are README plus changelog updates sufficient for this release?

## Outcome

Pending execution.

### Acceptance Verification

- [ ] A tagged release produces downloadable archives and checksums for all supported platforms and architectures
- [ ] README, `cli/README.md`, troubleshooting docs, and changelog document manual binary install from GitHub Releases as the primary path and no longer instruct users to install `yq`
- [ ] The Go binary can manage a project end-to-end using the documented install flow
- [ ] The Docker CLI image path remains available only as a clearly deprecated fallback during the transition
- [ ] Homebrew and installer-script work are called out as fast-follow, not hidden inside m13 scope

### Learnings

Pending execution.

### Follow-up Items

Pending execution.
