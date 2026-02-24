# Execution Log: m7.5 - CI Workflows

## 2026-02-23 - Implementation complete

Modified `build-images.yml`:
- Added `CODEX_IMAGE_NAME` env var
- Added `build-codex` job after `build-copilot`, mirrors its structure
- Version detection: `gh api repos/openai/codex/releases/latest --jq .tag_name` piped through `sed 's/^rust-v//'`
- Added `build-codex` to summary job needs array
- Added codex version and digest to summary output

Created `check-codex-version.yml`:
- Daily cron at 8am UTC (offset from Claude 6am, Copilot 7am)
- Step ID `github` instead of `npm` (reflects the version source)
- Summary table says "GitHub release latest" instead of "npm latest"
- Same pattern: check if `codex-{version}` tag exists in GHCR, trigger `build-images.yml` if not

**Decision:** Used `gh api` instead of `curl` for GitHub releases API. `gh` is pre-installed on GitHub Actions runners and handles authentication automatically via `GH_TOKEN`, avoiding rate limit issues with unauthenticated requests.
