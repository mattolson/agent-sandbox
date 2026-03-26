# Milestone: m12 - OpenCode Agent Support

## Goal

Add OpenCode (`opencode-ai`) as a supported agent in Agent Sandbox. Users can initialize, run, and switch to OpenCode via the standard `agentbox` workflow.

## Scope

**Included:**
- OpenCode agent Docker image (extends base, installs via npm)
- CLI templates (compose layer, devcontainer)
- CLI agent registry (agent.bash, tests)
- Proxy service domains and KNOWN_AGENTS
- build.sh support
- CI: build job in build-images.yml, version-check workflow
- Agent documentation (docs/agents/opencode.md)
- README update (supported agents table)

**Excluded:**
- Provider-specific proxy domains (users add claude/openai/gemini services to their policy based on which provider they use with OpenCode)
- OpenCode desktop app support (CLI-only)
- OpenCode server/remote mode integration
- OpenCode plugins or extensions

## Applicable Learnings

- Policy layering via Dockerfile COPY overwrites parent layer's policy cleanly
- Shared shell helpers that use `mapfile` must source `compat.bash`
- The add-agent skill provides a comprehensive checklist; follow it closely
- BATS tests reference agent list strings that must be updated in lockstep with agent.bash

## Tasks

### m12.1-dockerfile

**Summary:** Create the OpenCode agent Docker image.

**Scope:**
- `images/agents/opencode/Dockerfile` extending base image
- Install Node.js via NodeSource (same pattern as Pi/Factory/Copilot)
- Install `opencode-ai` via npm global install
- Create XDG directories for OpenCode state (`~/.config/opencode`, `~/.local/share/opencode`, `~/.cache/opencode`)
- Bake sandbox-friendly config: `opencode.json` granting all permissions (yolo mode) since there's no CLI flag
- Set `OPENCODE_DISABLE_AUTOUPDATE=true` and `OPENCODE_DISABLE_LSP_DOWNLOAD=true` to prevent network calls that would be blocked
- `OPENCODE_VERSION` build arg, image labels

**Acceptance Criteria:**
- `docker build` succeeds
- `docker run --rm agent-sandbox-opencode:local opencode --version` prints version
- Image follows existing Dockerfile conventions (EXTRA_PACKAGES, USER root/dev transitions)
- Baked config sets all permissions to allow

**Dependencies:** None

**Risks:** OpenCode uses XDG directories rather than a single dotdir. Need to ensure all three (config, data, cache) are created and the state volume covers the right path. The baked `opencode.json` with permission overrides needs verification against actual OpenCode behavior.

### m12.2-proxy-domains

**Summary:** Add OpenCode service domains and register OpenCode as a known agent in the proxy.

**Scope:**
- Add `"opencode"` entry to `SERVICE_DOMAINS` in `images/proxy/addons/enforcer.py`
- Add `"opencode"` to `KNOWN_AGENTS` in `images/proxy/render-policy`
- OpenCode service domains: `opencode.ai`, `models.dev` (model registry)
- Provider domains (Anthropic, OpenAI, Google, etc.) are user-managed, not part of the opencode service

**Acceptance Criteria:**
- Proxy starts with `AGENTBOX_ACTIVE_AGENT=opencode` without error
- OpenCode service domains resolve correctly in policy rendering
- Existing proxy tests still pass

**Dependencies:** None (independent of Dockerfile)

**Risks:** OpenCode is provider-agnostic like Pi. The opencode service covers only OpenCode infrastructure (`opencode.ai`, `models.dev`). Users must add the appropriate provider service to their policy. This should be documented clearly.

### m12.3-templates

**Summary:** Create CLI templates for OpenCode agent (compose layer and devcontainer).

**Scope:**
- `cli/templates/opencode/cli/agent.yml` — image ref, opencode-config and opencode-data and opencode-history volumes
- `cli/templates/opencode/devcontainer/devcontainer.json` — layered compose refs, no VS Code extensions (CLI-only agent), JetBrains proxy settings

**Acceptance Criteria:**
- `agentbox init --agent opencode --mode cli` generates valid compose stack
- `agentbox init --agent opencode --mode devcontainer` generates valid devcontainer config
- Compose config resolves without errors (`docker compose config`)

**Dependencies:** None (independent of other tasks)

**Risks:** OpenCode uses XDG directories, so volumes need to map to `~/.config/opencode` and `~/.local/share/opencode` rather than a single dotdir. Need to decide whether to use two named volumes or consolidate under one path.

### m12.4-cli-integration

**Summary:** Register OpenCode in the CLI agent registry and update tests.

**Scope:**
- Add `opencode` to `supported_agents_display()`, `supported_agents()`, `select_agent()`, `validate_agent()` in `cli/lib/agent.bash`
- Update BATS tests in `cli/test/init/init.bats` and `cli/test/switch/switch.bats` to include `opencode` in agent list assertions and stubs

**Acceptance Criteria:**
- `agentbox init --agent opencode` works
- `agentbox switch --agent opencode` works
- `cli/run-tests.bash` passes

**Dependencies:** m12.3 (templates must exist for init/switch to work)

**Risks:** None — mechanical addition to existing lists.

### m12.5-build-and-ci

**Summary:** Add OpenCode to build.sh and CI workflows.

**Scope:**
- Add `OPENCODE_VERSION`, `OPENCODE_EXTRA_PACKAGES` defaults, `build_opencode()` function, case entries in `images/build.sh`
- Add `OPENCODE_IMAGE_NAME` env var, `build-opencode` job in `.github/workflows/build-images.yml`
- Create `.github/workflows/check-opencode-version.yml` (daily cron, npm version check)
- Add OpenCode to summary job in build-images.yml

**Acceptance Criteria:**
- `./images/build.sh opencode` builds the OpenCode image
- `./images/build.sh all` includes OpenCode
- CI workflow YAML is valid (no syntax errors)
- Version check workflow follows existing pattern

**Dependencies:** m12.1 (Dockerfile must exist for build to work)

**Risks:** None — follows established CI pattern. Use 12pm UTC cron slot (Pi is 11am).

### m12.6-docs-and-readme

**Summary:** Add OpenCode agent documentation and update the project README.

**Scope:**
- Create `docs/agents/opencode.md` with setup, auth, and usage instructions
- Document that OpenCode is provider-agnostic: users must add the appropriate provider service to their policy
- Document sandbox-specific env vars (`OPENCODE_DISABLE_AUTOUPDATE`, `OPENCODE_DISABLE_LSP_DOWNLOAD`)
- Update `README.md` supported agents table with OpenCode row
- Update `docs/roadmap.md` to mark m12 as done
- Update `docs/plan/project.md` to mark m12 as done (after all tasks complete)

**Acceptance Criteria:**
- `docs/agents/opencode.md` covers authentication (provider API keys), usage, and provider policy setup
- README table includes OpenCode with correct status indicators
- Links are valid

**Dependencies:** All other tasks (docs describe the finished feature)

**Risks:** None.

## Execution Order

1. **m12.1** (Dockerfile) and **m12.2** (proxy) and **m12.3** (templates) — all independent, can be done in parallel
2. **m12.4** (CLI integration) — after m12.3
3. **m12.5** (build + CI) — after m12.1
4. **m12.6** (docs) — after everything else

Critical path: m12.3 -> m12.4 (CLI needs templates to exist).

## Risks

- **Provider-agnostic complexity**: Like Pi, OpenCode users choose their provider at runtime. The documentation must clearly explain that the `opencode` service only covers OpenCode infrastructure and users need to add provider-specific services. Mitigation: clear docs and a note in the agent.yml template comments.
- **XDG directory layout**: Unlike other agents that use a single `~/.agent` directory, OpenCode uses XDG paths (`~/.config/opencode`, `~/.local/share/opencode`, `~/.cache/opencode`). This means multiple volume mounts. Mitigation: use two named volumes (config + data) and let cache be ephemeral.
- **Permission config**: OpenCode has no `--dangerously-skip-permissions` flag. Yolo mode requires a baked `opencode.json` with all permissions set to `"allow"`. This needs testing to confirm it works as expected.

## Definition of Done

- `agentbox init --agent opencode` works in both CLI and devcontainer modes
- OpenCode image builds locally and via CI
- Proxy allows OpenCode-specific domains and blocks everything else
- `agentbox switch --agent opencode` works
- All existing CLI tests pass with OpenCode added
- Version-check workflow detects new OpenCode releases
- Documentation covers setup, auth, and provider policy configuration

## Changes

(None yet)
