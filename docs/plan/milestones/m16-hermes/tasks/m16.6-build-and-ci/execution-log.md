# Execution Log: m16.6 - Hermes build.sh, CI build job, and PyPI version-check workflow

## 2026-05-27 - All wiring complete + m16.2 Dockerfile bug surfaced and fixed

**Changes shipped:**

- `images/build.sh`: `HERMES_VERSION=latest` default, `HERMES_EXTRA_PACKAGES` default, `build_hermes()` function,
  `hermes` case entries in both pre-target and main case blocks (the pre-target one was easy to miss), `build_hermes`
  in the `all` target, plus updates to the file-header Usage comment, the main case Usage line, and the env-var
  doc section.
- `.github/workflows/build-images.yml`: `HERMES_IMAGE_NAME` env, new `build-hermes:` job (PyPI fetch via
  `curl ... | jq -r .info.version` instead of `npm view`), added to `summary.needs:` and the summary tables.
- `.github/workflows/check-hermes-version.yml`: new file, cron `0 13 * * *`, PyPI-based version check, tag pattern
  `hermes-${VERSION}`.

**Issue encountered during host-side build smoke:**

The default `./images/build.sh hermes` invocation failed with:

```
ERROR: Could not find a version that satisfies the requirement hermes-agent==latest
  (from versions: 0.13.0, 0.14.0)
ERROR: No matching distribution found for hermes-agent==latest
```

Root cause: build.sh's default `HERMES_VERSION=latest` was passed via `--build-arg` to the Dockerfile, overriding
the Dockerfile's `ARG HERMES_VERSION=0.14.0` (the pinned default I'd set in m16.2). Then the Dockerfile's
`pip install hermes-agent==latest` failed because PyPI/pip doesn't accept "latest" as a version constraint the way
npm does.

**Fix (folded into m16.6):** changed `images/agents/hermes/Dockerfile` to match the convention used by Codex:
- `ARG HERMES_VERSION=latest` (sentinel default)
- Conditional pip install: if version is the literal "latest", install unpinned; otherwise pin via `==${VERSION}`

After the fix: build with default `latest` succeeds (installs whatever PyPI ships at build time, current 0.14.0),
build with explicit `HERMES_VERSION=0.14.0` also succeeds (pinned). CI overrides with the resolved PyPI version,
so published images get proper version labels.

**Was this a m16.2 bug?** Yes — m16.2's Dockerfile chose to pin the ARG default to `0.14.0` rather than handle the
`latest` sentinel. At m16.2 time the test invoked `docker build` directly without `--build-arg`, so the bug
didn't surface. It only manifested when build.sh started passing `--build-arg HERMES_VERSION=$HERMES_VERSION` with
build.sh's default of `latest`. Folded the Dockerfile fix into this commit instead of amending m16.2.

**Validation:**
- `bash -n images/build.sh` clean.
- `yaml.safe_load` parses both workflow files; structurally:
  - `build-images.yml` jobs include `build-hermes`; `summary.needs` includes `build-hermes`.
  - `check-hermes-version.yml` cron is `0 13 * * *`.
- `./images/build.sh hermes` (default `latest`): builds successfully.
- `HERMES_VERSION=0.14.0 ./images/build.sh hermes`: builds successfully with explicit pin.
- `agent-sandbox-hermes:local` present in local docker daemon.

**Learning:** match upstream conventions for ARG defaults. Codex, Pi, OpenCode all use `ARG <AGENT>_VERSION=latest`
with the install step handling the sentinel. Deviating (pinning a specific version as the ARG default) creates a
hidden interaction with build.sh that only surfaces when both layers are exercised together. Going forward, new
agent Dockerfiles should use `latest` as the ARG default and put any sentinel handling in the RUN block.

**Status:** all acceptance criteria met, ready for commit.

## 2026-05-27 - Plan drafted

Mechanical task — three files touched, no design decisions remaining after m16.1/m16.2.

**Reference patterns surveyed:**

- `build.sh`: `build_pi()` and `build_opencode()` are nearly identical; both use the `BASE_IMAGE/<AGENT>_VERSION/
  EXTRA_PACKAGES` build-arg trio. Hermes uses the same shape, with `HERMES_VERSION=0.14.0` (PyPI semver, not git
  calver).
- `build-images.yml`: `build-pi:` is the closest reference job. Hermes copies it verbatim and swaps four things:
  the version-fetch step (`npm view` → `curl pypi.org/.../json | jq`), the build-arg name, the image-name env,
  and the registry tag prefix.
- `check-codex-version.yml`: the only existing non-npm version-check (Codex uses GitHub releases). Same control
  flow as the npm checks: fetch version → compute `<agent>-<version>` registry tag → `docker manifest inspect` →
  trigger `gh workflow run` if missing. Hermes swaps the fetch step for a PyPI curl.

**Cron slot decision:** 13:00 UTC. Existing slots are dense (06-12), so 13 is the next open hour. The m16.1
discovery already proposed this slot.

**One thing the milestone scope said but the discovery overrode:** the milestone says the version-check workflow
queries PyPI (right). The earlier discovery wording also mentioned an `api.github.com/.../releases/latest` shape
as an alternative — that one isn't needed; PyPI is simpler and authoritative once the publish workflow runs (the
calver tag triggers publish, so PyPI version mirrors the tag we'd want).

**Validation strategy inside sandbox:** YAML parsing via `python3 -c 'import yaml; yaml.safe_load(open(...))'`
catches structural syntax errors but won't catch GitHub Actions schema mistakes (e.g., misspelled `needs:` keys,
invalid `uses:` references). Those only surface in CI on push. Acceptable — m16.7 push will exercise the workflow
end-to-end.

Awaiting approval to execute.
