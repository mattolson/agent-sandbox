# Task: m16.4 - Hermes CLI and Devcontainer Templates

## Summary

Create the `internal/embeddata/templates/hermes/` directory with `cli/agent.yml` (compose layer) and
`devcontainer/devcontainer.json`. The Go `embed.FS` picks up new files under `templates/**` automatically at the
next build, so no code changes to the scaffold layer are needed — those tasks belong to m16.5.

## Scope

**Included:**
- `internal/embeddata/templates/hermes/cli/agent.yml` — compose layer for the agent service: image ref, named volume
  for `HERMES_HOME` (`/home/dev/.hermes`), named volume for shell history (`/commandhistory`).
- `internal/embeddata/templates/hermes/devcontainer/devcontainer.json` — devcontainer config layered over the standard
  compose files. Naming: "Hermes Sandbox". CLI-only agent so no VS Code extension list. JetBrains proxy settings copied
  verbatim.
- A small test in `internal/scaffold/templates_test.go` (or its sibling) that asserts the hermes template can be
  loaded via the embed FS, mirroring `TestReadTemplateLoadsNestedAgentTemplate`.

**Explicitly out of scope:**
- Registering `hermes` in `internal/runtime/agents.go` — that's m16.5. Templates can exist before the agent name is
  validated; the embed system doesn't gate on registry membership.
- `agentbox init --agent hermes` and `agentbox switch --agent hermes` end-to-end verification — gated by m16.5's
  agent-registry add. m16.4 stops at "template files exist and load via embed FS."
- Provider env-var forwarding in `agent.yml`. Reviewing Pi/OpenCode/Claude/Codex templates: none forward provider keys
  in the managed compose layer. The convention is: users authenticate via `hermes login` (writes credentials to the
  state volume) or add `environment:` entries to `.agent-sandbox/compose/user.agent.hermes.override.yml`. Per-task
  follow-up: m16.7's docs call out this pattern.
- `docker compose config` validation of the generated stack. That requires a working `agentbox init --agent hermes`
  flow which depends on m16.5. Defer to m16.5 or m16.7 manual verification.

## Acceptance Criteria

- [ ] `internal/embeddata/templates/hermes/cli/agent.yml` exists with the expected shape (managed-by-agentbox header,
      `services.agent.image`, `hermes-state` volume at `/home/dev/.hermes`, `hermes-history` volume at `/commandhistory`).
- [ ] `internal/embeddata/templates/hermes/devcontainer/devcontainer.json` exists with the expected shape (name
      "Hermes Sandbox", dockerComposeFile array pointing at base + agent.hermes + mode.devcontainer + the two override
      files, JetBrains proxy settings).
- [ ] A test in `internal/scaffold/templates_test.go` (or analogous) asserts the hermes template loads via the embed
      FS.
- [ ] `go test ./...` passes.
- [ ] No new `go vet` warnings.

## Applicable Learnings

From prior agent-add tasks (Pi, OpenCode) and m16.x context:

- **The managed `agent.yml` stays minimal.** Image + state volume + history volume. Anything user-specific (custom
  mounts, env vars, dotfiles) belongs in `user.override.yml` or `user.agent.<agent>.override.yml`. Don't bake
  provider keys into the managed template.
- **Devcontainer templates are mechanical.** Only the project name and the agent-named compose file path change
  between agents. CLI-only agents (Pi, OpenCode, Codex, Claude — all of them, actually) have no VS Code extensions
  listed; JetBrains proxy settings are identical across agents.
- **Embed FS picks up new files automatically.** `//go:embed templates/**` in `internal/embeddata/embeddata.go`
  glob-matches; no code edits needed to register new agent template subdirs.
- **State path matches the Dockerfile ENV.** m16.2 set `HERMES_HOME=/home/dev/.hermes`. The compose volume mount
  target must match exactly, or restart persistence breaks. Verified via `verify-hermes-managed.sh`.

## Plan

### Files Involved

To create:
- `internal/embeddata/templates/hermes/cli/agent.yml`
- `internal/embeddata/templates/hermes/devcontainer/devcontainer.json`

To modify:
- `internal/scaffold/templates_test.go` — add a hermes-equivalent of `TestReadTemplateLoadsNestedAgentTemplate`.

### Approach

1. **Compose layer:** copy `internal/embeddata/templates/pi/cli/agent.yml` as the starting template (Pi is the closest
   provider-agnostic agent with a single state directory like Hermes). Replace:
   - `agent-sandbox-pi` → `agent-sandbox-hermes`
   - `pi-state:/home/dev/.pi` → `hermes-state:/home/dev/.hermes`
   - `pi-history` → `hermes-history`
   - `user.agent.pi.override.yml` → `user.agent.hermes.override.yml`
   - `Pi config, credentials, and sessions` (in volume comment) → `Hermes state: learned skills, persona, sessions`
2. **Devcontainer:** copy `internal/embeddata/templates/pi/devcontainer/devcontainer.json`. Replace:
   - `"Pi Sandbox"` → `"Hermes Sandbox"`
   - `agent.pi.yml` → `agent.hermes.yml`
   - `user.agent.pi.override.yml` → `user.agent.hermes.override.yml`
3. **Test:** add a copy of the existing opencode/hermes embed-load assertion. Mirror exactly:
   ```go
   func TestReadTemplateLoadsHermesAgentTemplate(t *testing.T) {
       data, err := ReadTemplate("hermes/cli/agent.yml")
       if err != nil { t.Fatalf(...) }
       if !strings.Contains(string(data), "agent-sandbox-hermes") { t.Fatalf(...) }
   }
   ```
4. Run `go test ./...` to confirm the embed picks up the new files and the test passes.

### Implementation Steps

- [ ] Create `internal/embeddata/templates/hermes/cli/agent.yml` from Pi template.
- [ ] Create `internal/embeddata/templates/hermes/devcontainer/devcontainer.json` from Pi template.
- [ ] Add `TestReadTemplateLoadsHermesAgentTemplate` to `internal/scaffold/templates_test.go`.
- [ ] Run `go test ./...`.
- [ ] Run `go vet ./...` for cleanliness.

### Open Questions

None substantive. Pi is the closest reference (single state dir, provider-agnostic, no VS Code extensions). Hermes
inherits this shape exactly.

One small judgment call already settled: **no `environment:` block in the managed `agent.yml`.** Provider keys come
via `hermes login` (writes to the state volume) or via the user-owned override file. Matches the convention used by
every other agent template.

## Outcome

Completed 2026-05-27. Two templates + two tests, single pass.

### Acceptance Verification

- [x] `internal/embeddata/templates/hermes/cli/agent.yml` exists with expected shape
- [x] `internal/embeddata/templates/hermes/devcontainer/devcontainer.json` exists with expected shape
- [x] Tests assert both templates load via embed FS (`TestReadTemplateLoadsHermesAgentTemplate`,
      `TestReadTemplateLoadsHermesDevcontainerTemplate`)
- [x] `go test ./...` passes
- [x] `go vet ./...` clean

### Learnings

Nothing new to append to `docs/plan/learnings.md`. The embed FS auto-pickup, "managed agent.yml stays minimal" convention,
and Pi-as-reference pattern were already known from prior tasks.

### Follow-up Items

- **m16.5** needs to add `"hermes"` to `SupportedAgents()` in `internal/runtime/agents.go` and update any agent-list
  assertions in Go tests. Templates exist; the registry add is the unblock.
- **m16.7** docs should explain that direct env-var provider auth (e.g., `NOUS_API_KEY=...`) is added via
  `.agent-sandbox/compose/user.agent.hermes.override.yml`, not via the managed compose layer. The `hermes login`
  flow remains the easier path for OAuth-capable providers.
