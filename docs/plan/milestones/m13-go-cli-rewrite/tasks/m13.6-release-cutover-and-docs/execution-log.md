# Execution Log: m13.6 - Release Cutover And Docs

## 2026-04-07 05:46 UTC - Planning complete

Reviewed the `m13.6` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, `docs/plan/project.md`, `docs/plan/learnings.md`, decision `004`, the completed `m13.4` and `m13.5` task artifacts, the current Go CI and parity workflows in `.github/workflows/go-tests.yml` and `.github/workflows/parity-tests.yml`, the current image-publishing workflow in `.github/workflows/build-images.yml`, the existing Bash CLI image in `images/cli/Dockerfile`, and the user-facing install/docs surfaces in `README.md`, `cli/README.md`, `docs/troubleshooting.md`, `docs/roadmap.md`, and `CHANGELOG.md`.

The main planning conclusion is that `m13.6` should add a dedicated Go-binary release workflow and then do a documentation cutover around that artifact. The Go binary should become the primary install path in docs and releases, while the Docker CLI image remains available only as a clearly deprecated fallback during the transition. The Bash implementation should stay in-repo as the parity oracle until the new release path has shipped successfully.

**Issue:** The repo still tells users to clone `cli/bin`, install host `yq`, or pull `ghcr.io/mattolson/agent-sandbox-cli`, even though the Go rewrite now covers the full command surface and parity gates exist.
**Solution:** Plan `m13.6` as a combined release-automation plus documentation cutover task. Add a dedicated workflow for tagged Go binary releases with checksums, then update README, CLI docs, troubleshooting, changelog, and roadmap together so the primary install story changes in one move.

**Decision:** Recommend a dedicated Go-binary release workflow instead of extending the existing image workflow. The artifact model, version stamping, and user-facing output are different enough that keeping release assets separate from GHCR image publishing will make the cutover clearer and easier to maintain.

**Learning:** Distribution cutovers fail when the code is ready but the docs and release machinery still point at the previous path. For `m13.6`, the highest-risk drift is between release automation and user-facing install guidance, not between the Go and Bash command semantics.
