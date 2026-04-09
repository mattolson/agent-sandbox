# Execution Log: m13.6 - Release Cutover And Docs

## 2026-04-09 03:52 UTC - Simplified install copy for first-time readers

Removed rollout phrasing like "primary supported install path" and "(recommended)" from the GitHub Releases install copy in `README.md`, and simplified the top of `cli/README.md` so it reads as a straightforward install-reference handoff instead of internal migration language.

## 2026-04-09 03:48 UTC - Simplified top-level install docs

Removed the deprecated Docker-image fallback section from `README.md` so the top-level install story now shows only the Go binary path, and moved that fallback discussion into `cli/README.md` instead.

**Decision:** Keep the main README singular about installation. The deprecated Docker image is still relevant, but it belongs in the CLI reference and troubleshooting surfaces rather than beside the primary install path.

## 2026-04-09 03:40 UTC - Added stable latest-download asset names

Extended `scripts/build-release-artifacts.bash` so each release now emits both versioned archives such as `agentbox_0.8.0_linux_arm64.tar.gz` and stable unversioned archives such as `agentbox_linux_arm64.tar.gz`, plus a stable `agentbox_checksums.txt` manifest. Updated `README.md` to use the unversioned `releases/latest/download/...` path for the convenience install flow.

Local verification passed by rebuilding `/tmp/agentbox-release-test`, confirming the unversioned assets exist, extracting `agentbox_linux_arm64.tar.gz`, and running the extracted binary's `version` command successfully.

**Issue:** Publishing only versioned archive names meant users could not use GitHub's `releases/latest/download/<asset>` shortcut without first resolving the latest tag. A naive copy to an unversioned tarball name was also insufficient because the archive still unpacked into a versioned directory.
**Solution:** Emit a second set of archives with stable filenames and stable unpack paths, and add a matching stable checksum manifest for those assets.

**Learning:** Stable download URLs require stable artifact names and stable archive contents. Convenience assets need to be designed intentionally rather than derived as a last-minute copy of versioned outputs.

## 2026-04-08 05:25 UTC - Release workflow, packaging helper, and docs cutover implemented

Added `scripts/build-release-artifacts.bash` to build tagged macOS and Linux archives with checksum output and explicit `ldflags` version metadata, added `.github/workflows/release-go-binaries.yml` to run Go tests plus parity before creating or updating a draft GitHub release on version tags, and updated `README.md`, `cli/README.md`, `docs/troubleshooting.md`, `docs/roadmap.md`, and `CHANGELOG.md` so GitHub Releases binaries are the primary install path and the Docker CLI image is only a deprecated fallback.

Local verification passed with `bash -n scripts/build-release-artifacts.bash`, `go test ./...`, `./scripts/parity.bash`, `scripts/build-release-artifacts.bash --version v0.8.0 --out-dir /tmp/agentbox-release-test`, checksum verification of the native archive, `agentbox version` from the extracted binary, and `agentbox init --batch` from that extracted binary against a temp repo using local image refs.

**Issue:** The first packaging-helper smoke test failed because it assumed the version command printed `agentbox <version>` and because local dirty-worktree builds legitimately gained a `-dirty` suffix.
**Solution:** Relax the smoke check to assert the expected version string and `source: ldflags` instead of one exact command banner, and allow local verification to override `BUILD_DIRTY=false` when simulating a clean release build.

**Decision:** Keep release packaging logic in a small repo-owned shell helper plus one dedicated workflow, and keep the old Docker CLI image untouched for `m13.6` rather than mixing distribution cutover with fallback implementation changes.

**Learning:** `go version -m` provides a lightweight metadata validation path for cross-compiled release artifacts, which makes it practical to sanity-check all four target binaries even though only the native host-target pair can be executed directly in local verification.

## 2026-04-07 05:48 UTC - Deprecated fallback stays unchanged for m13.6

Chose to keep the deprecated Docker CLI fallback as-is for `m13.6`. This task will cut over the primary distribution path to GitHub Releases binaries and documentation, but it will not repoint `images/cli/Dockerfile` at the Go binary or start removing the old Bash CLI yet.

**Decision:** Leave the fallback image and old CLI implementation unchanged during `m13.6`, and create follow-up work to remove the old CLI and decide whether the fallback image should switch codepaths first or disappear entirely.

**Rationale:** Mixing distribution cutover, fallback-image implementation changes, and legacy CLI removal in one task would blur the acceptance boundary and raise rollback risk. Keeping the fallback untouched makes `m13.6` narrower: ship the Go binary, update the docs, and deprecate the old path without changing its runtime behavior.

## 2026-04-07 05:47 UTC - Release trigger direction chosen

Chose the two-step release model for `m13.6`: tag push builds versioned archives and checksums, uploads them to a draft or otherwise unpublished GitHub release, and a separate human publish step makes the release public after notes and assets are confirmed.

**Decision:** Use a two-step release flow instead of triggering binary packaging from `release.published`. The tag remains the build source of truth, but publication waits until artifacts exist.

**Rationale:** This avoids the main failure mode of `release.published`: a public release page with missing or partial assets if packaging fails halfway through. It also keeps recovery simpler because draft assets can be rebuilt or re-uploaded without retagging.

## 2026-04-07 05:46 UTC - Planning complete

Reviewed the `m13.6` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, `docs/plan/project.md`, `docs/plan/learnings.md`, decision `004`, the completed `m13.4` and `m13.5` task artifacts, the current Go CI and parity workflows in `.github/workflows/go-tests.yml` and `.github/workflows/parity-tests.yml`, the current image-publishing workflow in `.github/workflows/build-images.yml`, the existing Bash CLI image in `images/cli/Dockerfile`, and the user-facing install/docs surfaces in `README.md`, `cli/README.md`, `docs/troubleshooting.md`, `docs/roadmap.md`, and `CHANGELOG.md`.

The main planning conclusion is that `m13.6` should add a dedicated Go-binary release workflow and then do a documentation cutover around that artifact. The Go binary should become the primary install path in docs and releases, while the Docker CLI image remains available only as a clearly deprecated fallback during the transition. The Bash implementation should stay in-repo as the parity oracle until the new release path has shipped successfully.

**Issue:** The repo still tells users to clone `cli/bin`, install host `yq`, or pull `ghcr.io/mattolson/agent-sandbox-cli`, even though the Go rewrite now covers the full command surface and parity gates exist.
**Solution:** Plan `m13.6` as a combined release-automation plus documentation cutover task. Add a dedicated workflow for tagged Go binary releases with checksums, then update README, CLI docs, troubleshooting, changelog, and roadmap together so the primary install story changes in one move.

**Decision:** Recommend a dedicated Go-binary release workflow instead of extending the existing image workflow. The artifact model, version stamping, and user-facing output are different enough that keeping release assets separate from GHCR image publishing will make the cutover clearer and easier to maintain.

**Learning:** Distribution cutovers fail when the code is ready but the docs and release machinery still point at the previous path. For `m13.6`, the highest-risk drift is between release automation and user-facing install guidance, not between the Go and Bash command semantics.
