# Task: m17.1 - gh in base image

## Summary

Ship a pinned stock `gh` in the base image.

## Scope

- Install `gh` from the official release tarball for both architectures with a pinned `GH_VERSION` and checksum
  verification, following the `GIT_VERSION` pattern in `images/base/Dockerfile`
- Set `GH_NO_UPDATE_NOTIFIER=1` and `GH_PROMPT_DISABLED=1` in the image so `gh` never calls the `cli/cli` release
  endpoint or waits on a prompt
- Decide how the pin gets refreshed
- Confirm `gh` honors `HTTPS_PROXY` and the installed proxy CA, and that HTTP/2 through mitmproxy works or is disabled

## Acceptance Criteria

- [x] `gh --version` in a fresh container prints the pinned version: arm64 verified on the rebuilt dev image;
      amd64 is produced by the CI build job
- [x] `gh api` reaches the proxy and gets a policy decision, not a TLS or connection error
- [x] No `gh` process makes a request outside the configured policy at startup

## Applicable Learnings

- Git is the precedent for a hand-pinned, checksum-verified tarball in the base image. Dependabot cannot see either.
- `gh` is a Go binary. The compose stack sets `GODEBUG=http2client=0` for the agent container, which is what let the
  validation run work through mitmproxy.
- The 2026-09-06 validation found `gh` release assets redirect to `release-assets.githubusercontent.com`. That only
  matters when downloading inside a sandbox; the image build runs on the host or in CI.

## Plan

### Files Involved

- `images/base/Dockerfile`: new pinned download block and two `ENV` lines
- `images/build.sh`: `GH_VERSION`, `GH_SHA256_AMD64`, `GH_SHA256_ARM64` defaults and build args
- `docs/images.md`: how the pin is refreshed

### Approach

Add a `RUN` after the yq step that resolves `TARGETARCH` (BuildKit sets it; fall back to `dpkg --print-architecture`
for the legacy builder), selects the matching checksum, downloads the release tarball, verifies it with `sha256sum -c`,
installs `bin/gh` to `/usr/local/bin`, and asserts `gh --version`. Two checksum args instead of one because the
tarball differs per architecture, unlike the Git source tarball.

Refresh stays manual, mirroring Git. A scheduled check workflow could open an issue when a newer release exists, but
the agent version checks exist because agent releases are weekly and user-visible; gh releases are neither. Revisit
if the pin rots.

### Implementation Steps

- [x] Dockerfile download, verify, install, and version assertion
- [x] `ENV GH_NO_UPDATE_NOTIFIER=1` and `ENV GH_PROMPT_DISABLED=1`
- [x] Plumb the three build args through `images/build.sh`
- [x] Document the refresh procedure in `docs/images.md`
- [x] Smoke-test the exact shell sequence against the downloaded arm64 tarball
- [x] Build the base image on the host and confirm `gh --version` (arm64; amd64 via CI)

### Open Questions

- None. The CI base job uses Dockerfile defaults and builds both platforms, so no workflow change is needed.

## Outcome

### Acceptance Verification

- [x] Fresh-container `gh --version`: `gh version 2.100.0` from `/usr/local/bin/gh` on the rebuilt arm64 image
- [x] `gh api` through the proxy: proven in the 2026-09-06 validation with the same binary and version
- [x] No startup side requests: proven in the validation with `GH_DEBUG=api` and `GH_NO_UPDATE_NOTIFIER=1`

### Learnings

- Per-architecture release tarballs need per-architecture checksums, so the single-hash Git pattern does not carry
  over directly. `TARGETARCH` plus a `case` keeps one `RUN` for both.

### Follow-up Items

- None. amd64 is covered by the CI build matrix.
