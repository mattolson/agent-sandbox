# Task: m7.5 - CI Workflows

## Summary

Add GitHub Actions build job and daily version check for Codex.

## Scope

- Add `CODEX_IMAGE_NAME` env var to `build-images.yml`
- Add `build-codex` job following the Claude/Copilot pattern
- Version detection via GitHub releases API (not npm)
- Add to summary job
- Create `.github/workflows/check-codex-version.yml` (daily cron at 8am UTC)

## Acceptance Criteria

- [x] Push to main builds and publishes codex image to GHCR
- [x] Daily cron detects new Codex releases and triggers rebuild
- [x] Image tagged with `latest`, `sha-<commit>`, and `codex-X.Y.Z`

## Plan

### Files Involved

- `.github/workflows/build-images.yml` (modify)
- `.github/workflows/check-codex-version.yml` (new)

### Approach

**build-images.yml**: Add `build-codex` job that mirrors `build-copilot`. Key difference: version detection uses `gh api repos/openai/codex/releases/latest --jq .tag_name` then strips `rust-v` prefix via sed, rather than querying npm. Build arg is `CODEX_VERSION` instead of `COPILOT_VERSION`.

**check-codex-version.yml**: Mirrors `check-copilot-version.yml`. Same structure, different version source (GitHub releases API instead of npm). Cron at 8am UTC (Claude is 6am, Copilot is 7am). Tag prefix `codex-` for registry check.

### Implementation Steps

- [x] Add `CODEX_IMAGE_NAME` env var
- [x] Add `build-codex` job with GitHub releases version detection
- [x] Add `build-codex` to summary job needs and output
- [x] Create `check-codex-version.yml` with daily cron

## Outcome

### Acceptance Verification

- [x] `build-codex` job: needs `build-base`, uses `gh api` for version, passes `CODEX_VERSION` build arg, tags with `codex-{version}`
- [x] Summary job includes `build-codex` in needs array and outputs codex version and digest
- [x] Version check: daily 8am UTC cron, queries GitHub releases API, strips `rust-v` prefix, checks for `codex-{version}` tag in GHCR, triggers rebuild if missing

### Learnings

- Codex version detection differs from Claude/Copilot (GitHub releases API vs npm). The `gh api` command is available in GitHub Actions runners by default, so no extra setup needed.
- The `/releases/latest` endpoint automatically skips pre-releases, which is the right behavior for stable builds.

### Follow-up Items

None.
