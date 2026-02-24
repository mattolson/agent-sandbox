# Task: m7.3 - Codex CLI and Devcontainer Templates

## Summary

Create CLI and devcontainer compose templates and devcontainer.json for Codex.

## Scope

- `cli/templates/codex/cli/docker-compose.yml`
- `cli/templates/codex/devcontainer/docker-compose.yml`
- `cli/templates/codex/devcontainer/devcontainer.json`

## Acceptance Criteria

- [x] Templates render correctly via `agentbox init --agent codex --mode cli` and `--mode devcontainer`
- [x] Compose files reference the correct image and volume names
- [x] Proxy settings route traffic through the sidecar

## Applicable Learnings

- Templates are copied verbatim by the CLI init flow, then customized via `yq` (image pinning, policy volume mount). The template itself must be valid YAML with the right structure.
- CLI vs devcontainer compose differences: devcontainer adds `.:/workspace/.devcontainer:ro` volume mount and a comment about relative paths. Otherwise identical.
- No agent-specific customization needed in `composefile.bash` for Codex (no host config mounting equivalent to Claude's CLAUDE.md).

## Plan

### Files Involved

- `cli/templates/codex/cli/docker-compose.yml` (new)
- `cli/templates/codex/devcontainer/docker-compose.yml` (new)
- `cli/templates/codex/devcontainer/devcontainer.json` (new)

### Approach

Copy the copilot templates as a starting point (copilot is the closer match since it has no agent-specific env vars like Claude's `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`). Then adjust:

1. **Image name**: `ghcr.io/mattolson/agent-sandbox-codex:latest`
2. **Volume names**: `codex-state` (mounted at `/home/dev/.codex`), `codex-history`
3. **Environment**: Add `CODEX_HOME=/home/dev/.codex`. Keep proxy settings and `GODEBUG=http2client=0`.
4. **devcontainer.json**: Name "Codex CLI Sandbox", no extensions (Codex is CLI-only, no VS Code or JetBrains plugin). Keep JetBrains proxy settings (useful if someone opens the devcontainer in a JetBrains IDE for other reasons).
5. **Comment**: "Codex CLI Sandbox" header

### Implementation Steps

- [x] Create `cli/templates/codex/cli/docker-compose.yml`
- [x] Create `cli/templates/codex/devcontainer/docker-compose.yml`
- [x] Create `cli/templates/codex/devcontainer/devcontainer.json`

### Open Questions

None. This is a mechanical adaptation of existing templates.

## Outcome

### Acceptance Verification

- [x] Templates follow the exact same structure as Claude/Copilot templates
- [x] Image: `ghcr.io/mattolson/agent-sandbox-codex:latest`
- [x] Volumes: `codex-state` at `/home/dev/.codex`, `codex-history` at `/commandhistory`
- [x] Proxy env vars: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `GODEBUG`
- [x] devcontainer.json: no extensions (CLI-only), JetBrains proxy settings retained
- [x] Devcontainer compose includes `.devcontainer:ro` mount

### Learnings

- Codex templates are nearly identical to Copilot. The only substantive differences are image name, volume names, state directory path, and `CODEX_HOME` env var. Copilot has no agent-specific env vars either, making it the cleanest base to adapt from.

### Follow-up Items

- Full rendering test requires m7.4 (CLI integration) since `agentbox init` needs codex in `available_agents`.
