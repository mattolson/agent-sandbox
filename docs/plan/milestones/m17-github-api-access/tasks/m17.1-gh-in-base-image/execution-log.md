# Execution Log: m17.1 - gh in base image

## 2026-09-06 - Install block written and smoke-tested

Added the pinned `gh` download to `images/base/Dockerfile` after the yq step, plumbed `GH_VERSION` and the two
checksums through `images/build.sh`, and documented the manual refresh in `docs/images.md`.

**Issue:** No Docker inside the sandbox, so the Dockerfile cannot be built here.
**Solution:** Ran the exact `RUN` shell sequence against the `gh 2.100.0` arm64 tarball already downloaded during the
m17 validation, with `TARGETARCH` deliberately empty to exercise the `dpkg` fallback. Checksum verified, binary
installed, version assertion passed. The host build remains a follow-up.

**Decision:** Two checksum build args (`GH_SHA256_AMD64`, `GH_SHA256_ARM64`) rather than one, because the tarball
differs per architecture. The `case` on `TARGETARCH` picks the right one and fails loudly for anything else.

**Decision:** Refresh stays manual, like Git. No `check-gh-version.yml`. The agent version checks exist because agent
releases are frequent and user-visible; a gh bump is neither. Recorded in the task plan so it can be revisited.

**Learning:** The `build.sh` usage comment suggested `EXTRA_PACKAGES="jq gh"` as an example. Both are now built in,
so the example was changed to avoid implying a second install path for gh.
