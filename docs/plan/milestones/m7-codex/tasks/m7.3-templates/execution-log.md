# Execution Log: m7.3 - Codex CLI and Devcontainer Templates

## 2026-03-06 - Follow-up cleanup

Removed the redundant `CODEX_HOME=/home/dev/.codex` environment variable from both Codex compose templates. The state volume already mounts the default config directory, so the env var did not change behavior and only made the templates diverge from the cleaner Copilot baseline.

**Decision:** Keep only proxy-related environment variables and `GODEBUG` in the Codex templates. Avoid restating tool defaults unless the image or entrypoint changes the expected config path.

## 2026-02-23 - Implementation complete

Created all three template files by adapting the copilot templates:

- `cli/templates/codex/cli/docker-compose.yml` - CLI mode
- `cli/templates/codex/devcontainer/docker-compose.yml` - devcontainer mode (adds `.devcontainer:ro` mount)
- `cli/templates/codex/devcontainer/devcontainer.json` - no extensions, keeps JetBrains proxy settings

Changes from copilot templates:
- Image: `agent-sandbox-codex` (was `agent-sandbox-copilot`)
- Volumes: `codex-state` at `/home/dev/.codex` (was `copilot-state` at `/home/dev/.copilot`)
- Volumes: `codex-history` (was `copilot-history`)
- Environment: kept proxy settings and `GODEBUG=http2client=0`
- Volume comment: "Persist Codex config and credentials" (was "Persist Copilot credentials")
- devcontainer.json: name "Codex CLI Sandbox", no `extensions` arrays (Codex is CLI-only)

## 2026-02-23 - Planning

Reviewed all existing templates (Claude CLI, Claude devcontainer, Copilot CLI, Copilot devcontainer). Copilot is the closer analog since it has no agent-specific env vars beyond the standard proxy settings. Claude adds `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`.
