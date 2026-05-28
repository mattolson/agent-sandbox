# Task: m16.6 - Hermes build.sh, CI build job, and PyPI version-check workflow

## Summary

Wire `agent-sandbox-hermes` into the local build script (`images/build.sh`) and the CI image-build pipeline
(`.github/workflows/build-images.yml`), and add a daily version-check workflow that queries PyPI (not npm) for new
Hermes releases and triggers a rebuild when the tag isn't yet in ghcr.

## Scope

**Included:**
- `images/build.sh`: `HERMES_VERSION` default (`latest`), `HERMES_EXTRA_PACKAGES` reference, `build_hermes()`
  function, `hermes` case entry, append `build_hermes` to the `all` target, update usage banner (Usage line +
  env-var docs).
- `.github/workflows/build-images.yml`: `HERMES_IMAGE_NAME` env, new `build-hermes` job mirroring `build-pi` but
  with a PyPI fetch step instead of `npm view`, add `build-hermes` to the `summary` job's `needs:` and the summary
  output table.
- `.github/workflows/check-hermes-version.yml`: new file modeled on `check-codex-version.yml` (closest existing
  non-npm reference; Codex queries GitHub releases via `gh api`). Our PyPI fetch uses
  `curl -fsSL https://pypi.org/pypi/hermes-agent/json | jq -r .info.version`. Daily cron at **13:00 UTC** (next
  unused slot after OpenCode at 12:00).
- Local validation: `./images/build.sh hermes` produces an image; `./images/build.sh all` includes Hermes; both
  workflow YAML files parse cleanly via a `yaml.safe_load` round-trip.

**Explicitly out of scope:**
- Hermes pinned-image bumping in `internal/embeddata/templates/hermes/cli/agent.yml`. That stays at `:latest`
  because `docker.ResolvePinnedImage` pulls a digest at `agentbox init` time. The first published image is what
  the resolver sees.
- `docs/agents/hermes.md` updates — m16.7.
- README support-matrix updates — m16.7.
- Tag-publishing release flow — handled by the existing build-images.yml infrastructure once Hermes is wired in.

## Acceptance Criteria

- [ ] `images/build.sh hermes` builds `agent-sandbox-hermes:local` successfully on host.
- [ ] `images/build.sh all` includes Hermes in the build sequence (verifiable by running it dry, or by reading the
      shell case to confirm).
- [ ] `images/build.sh` (with no args) usage banner lists `hermes` in the targets and mentions `HERMES_VERSION` and
      `HERMES_EXTRA_PACKAGES`.
- [ ] `.github/workflows/build-images.yml` validates as YAML (`yaml.safe_load`). The new `build-hermes` job's shape
      is structurally identical to `build-pi` except: (a) PyPI fetch step replaces npm fetch step, (b) image-name env
      var is `HERMES_IMAGE_NAME`, (c) tag pattern is `hermes-${VERSION}`. The `summary` job's `needs:` list and
      Markdown table both include hermes.
- [ ] `.github/workflows/check-hermes-version.yml` validates as YAML, has cron `0 13 * * *`, queries PyPI, registers
      the `hermes-${VERSION}` tag check against ghcr, and triggers `build-images.yml` when the tag doesn't exist.
- [ ] No regressions in any other workflow file (touched files only).

## Applicable Learnings

From prior agent-add tasks:

- **build.sh agent-add pattern is mechanical.** Mirror Pi/OpenCode's `build_<agent>()` function shape exactly:
  uses `BASE_IMAGE=agent-sandbox-base:$TAG`, passes `<AGENT>_VERSION` and `EXTRA_PACKAGES=<AGENT>_EXTRA_PACKAGES`
  through `--build-arg`, tags `agent-sandbox-<agent>:$TAG`.
- **CI build job pattern is mechanical too.** `build-pi` is the closest reference — single-arch-agnostic, no
  external auth (no Anthropic OAuth handshake like Claude). The only difference for Hermes is the version-fetch
  step: PyPI JSON via `curl + jq`, not `npm view`.
- **Version-check workflow has a non-npm precedent.** `check-codex-version.yml` uses `gh api repos/.../releases/latest`
  via GitHub releases. For Hermes we use PyPI's `/pypi/<pkg>/json` endpoint — same shape (fetch version, compute
  `<agent>-<version>` registry tag, `docker manifest inspect` to check exists, `gh workflow run` to trigger rebuild
  if missing).
- **Cron slot allocation.** Existing slots: claude 06, copilot 07, codex 08, gemini 09, factory 10, pi 11,
  opencode 12. Hermes takes 13.
- **PyPI vs git-tag form (from m16.2 spike).** PyPI returns the semver string (e.g. `0.14.0`), not the git calver
  tag (`v2026.5.16`). The `HERMES_VERSION` build arg and the `hermes-<version>` registry tag both use the PyPI
  semver form.

## Plan

### Files Involved

To modify:
- `images/build.sh`
- `.github/workflows/build-images.yml`

To create:
- `.github/workflows/check-hermes-version.yml`

### Approach

1. **build.sh edits.** Add `HERMES_VERSION=latest` default (~line 65, alphabetical-ish next to OpenCode). Add
   `build_hermes()` function (model on `build_opencode`, drop in HERMES variable names and the
   `images/agents/hermes` context path). Insert `hermes) build_hermes ;;` case (alphabetical). Append `build_hermes`
   to the `all` target. Update the Usage line and the env-var doc lines (`HERMES_VERSION`, `HERMES_EXTRA_PACKAGES`).
2. **build-images.yml edits.** Add `HERMES_IMAGE_NAME` to the top-level `env:` block (alphabetically next to
   `GEMINI_IMAGE_NAME`). Copy the entire `build-pi:` job, rename to `build-hermes:`, swap:
   - Job output: `hermes_version`
   - Version step: replace `npm view @mariozechner/pi-coding-agent@latest version` with
     `curl -fsSL https://pypi.org/pypi/hermes-agent/json | jq -r .info.version`.
   - Step name: `Get latest hermes-agent version from PyPI`.
   - Tag prefix: `hermes-${{ steps.version.outputs.version }}`.
   - Build arg: `HERMES_VERSION=${{ steps.version.outputs.version }}`.
   - Context: `./images/agents/hermes`.
   - Image-name env: `HERMES_IMAGE_NAME`.
   Place the job after `build-opencode:` and before `summary:`. Update `summary.needs:` to add `build-hermes`. Add a
   `**Hermes version:** ...` line to the markdown summary and a `| agent-sandbox-hermes | \`${{ ... }}\` |` row to
   the digest table.
3. **check-hermes-version.yml creation.** Start from `check-codex-version.yml` (closest non-npm shape). Swap the
   `gh api repos/.../releases/latest` step for a PyPI curl+jq step. Cron line: `0 13 * * *  # Daily at 13 UTC ...`.
   IMAGE_NAME: `agent-sandbox-hermes`. Tag prefix: `hermes-`. Summary header: `Hermes Agent Version Check`.
4. **Validation:**
   - YAML parse both workflow files with `/opt/proxy-python/bin/python3 -c 'import yaml,sys;
     yaml.safe_load(open(sys.argv[1]))' <file>` to catch syntax errors before CI sees them.
   - Run `./images/build.sh hermes` locally (on host; host has docker).
   - Eyeball the usage banner output.
   - Verify the change list with `git diff --stat`.

### Implementation Steps

- [ ] Edit `images/build.sh`: defaults, `build_hermes()`, case, all, usage banner. Five distinct edits in one file.
- [ ] Edit `.github/workflows/build-images.yml`: env, new build-hermes job, summary updates.
- [ ] Create `.github/workflows/check-hermes-version.yml`.
- [ ] YAML-parse both workflow files. (Inside this sandbox; doesn't need host.)
- [ ] User runs `./images/build.sh hermes` on host to confirm the build target works end-to-end (cached layer hit
      from m16.2's earlier build).
- [ ] User runs `./images/build.sh all` on host or scans the case statement to confirm hermes is in the all target.

### Open Questions

None substantive. The patterns are mechanical and the m16.1 discovery + m16.2 spike pinned the version source and
tag format.

One small judgment call already settled: **use `jq` not `python` for the PyPI version parse**, mirroring how
`check-codex-version.yml` uses `gh api --jq` rather than parsing JSON with Python. ubuntu-latest runners have both;
jq is the simpler one-liner.

## Outcome

Completed 2026-05-27. Three files modified, one new workflow created, plus a m16.2 Dockerfile bug fixed in the
same commit.

### Acceptance Verification

- [x] `./images/build.sh hermes` builds `agent-sandbox-hermes:local` (verified on host)
- [x] `./images/build.sh all` includes hermes (verified by source inspection of the case block)
- [x] build.sh usage banner (file-header comment + main case Usage line) lists hermes; env-var doc mentions
      `HERMES_VERSION` and `HERMES_EXTRA_PACKAGES`
- [x] `build-images.yml` parses cleanly; `build-hermes` job structurally mirrors `build-pi` with PyPI fetch instead
      of `npm view`; `summary.needs` and tables include hermes
- [x] `check-hermes-version.yml` parses cleanly; cron is `0 13 * * *`; queries PyPI; tag check uses `hermes-${VERSION}`
- [x] `HERMES_VERSION` env-var override works (verified explicitly with `HERMES_VERSION=0.14.0`)

### Learnings

Appended to `docs/plan/learnings.md`:

- Match upstream conventions for `ARG <AGENT>_VERSION` defaults: use `latest` as the sentinel and put any
  install-source-specific handling in the RUN block. Deviating (pinning a specific version as the ARG default)
  creates a hidden interaction with `build.sh`'s `HERMES_VERSION=latest` default that only surfaces when both layers
  are exercised together.

### Follow-up Items

- **m16.7** picks up the host-side end-to-end run: `agentbox init --agent hermes`, `agentbox up`, a real interactive
  Hermes session, restart-persistence of `HERMES_HOME`.
- **First CI build run** after merge will exercise the new `build-hermes` job and version-check workflow end-to-end.
  Workflow-schema bugs (misspelled `needs:` keys, etc.) can only surface there. If anything's wrong, fix-forward in
  a small follow-up.
