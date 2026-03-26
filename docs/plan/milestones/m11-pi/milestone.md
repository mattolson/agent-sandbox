# Milestone: m11 - Pi Agent Support

## Goal

Add Pi coding agent (`@mariozechner/pi-coding-agent`) as a supported agent in Agent Sandbox. Users can initialize, run, and switch to Pi via the standard `agentbox` workflow.

## Scope

**Included:**
- Pi agent Docker image (extends base, installs via npm)
- CLI templates (compose layer, devcontainer)
- CLI agent registry (agent.bash, tests)
- Proxy service domains and KNOWN_AGENTS
- build.sh support
- CI: build job in build-images.yml, version-check workflow
- Agent documentation (docs/agents/pi.md)
- README update (supported agents table)

**Excluded:**
- Provider-specific proxy domains (users add claude/codex/gemini services to their policy based on which provider they use with Pi)
- Pi extensions/packages support (user responsibility)
- Pi SDK or RPC mode integration

## Applicable Learnings

- Policy layering via Dockerfile COPY overwrites parent layer's policy cleanly
- Shared shell helpers that use `mapfile` must source `compat.bash`
- The add-agent skill provides a comprehensive checklist; follow it closely
- BATS tests reference agent list strings that must be updated in lockstep with agent.bash

## Tasks

### m11.1-dockerfile

**Summary:** Create the Pi agent Docker image.

**Scope:**
- `images/agents/pi/Dockerfile` extending base image
- Install Node.js via NodeSource (same pattern as Factory/Copilot)
- Create `~/.pi` config directory
- Install `@mariozechner/pi-coding-agent` via npm global install
- `PI_VERSION` build arg, image labels

**Acceptance Criteria:**
- `docker build` succeeds
- `docker run --rm agent-sandbox-pi:local pi --version` prints version
- Image follows existing Dockerfile conventions (EXTRA_PACKAGES, USER root/dev transitions)

**Dependencies:** None

**Risks:** None — straightforward npm install, same pattern as Factory.

### m11.2-proxy-domains

**Summary:** Add Pi service domains and register Pi as a known agent in the proxy.

**Scope:**
- Add `"pi"` entry to `SERVICE_DOMAINS` in `images/proxy/addons/enforcer.py`
- Add `"pi"` to `KNOWN_AGENTS` in `images/proxy/render-policy`
- Pi service defined with empty domain list (Pi's core operation requires only provider domains, which users add separately)

**Acceptance Criteria:**
- Proxy starts with `AGENTBOX_ACTIVE_AGENT=pi` without error
- Pi service domains resolve correctly in policy rendering
- Existing proxy tests still pass

**Dependencies:** None (independent of Dockerfile)

**Risks:** Pi is provider-agnostic. The Pi service covers only Pi-specific infrastructure. Users must add the appropriate provider service (claude, codex, gemini, copilot) to their policy. This should be documented clearly.

### m11.3-templates

**Summary:** Create CLI templates for Pi agent (compose layer and devcontainer).

**Scope:**
- `cli/templates/pi/cli/agent.yml` — image ref, pi-state and pi-history volumes
- `cli/templates/pi/devcontainer/devcontainer.json` — layered compose refs, no VS Code extensions (CLI-only agent), JetBrains proxy settings

**Acceptance Criteria:**
- `agentbox init --agent pi --mode cli` generates valid compose stack
- `agentbox init --agent pi --mode devcontainer` generates valid devcontainer config
- Compose config resolves without errors (`docker compose config`)

**Dependencies:** None (independent of other tasks)

**Risks:** None — follows established template pattern.

### m11.4-cli-integration

**Summary:** Register Pi in the CLI agent registry and update tests.

**Scope:**
- Add `pi` to `supported_agents_display()`, `supported_agents()`, `select_agent()`, `validate_agent()` in `cli/lib/agent.bash`
- Update BATS tests in `cli/test/init/init.bats` and `cli/test/switch/switch.bats` to include `pi` in agent list assertions and stubs

**Acceptance Criteria:**
- `agentbox init --agent pi` works
- `agentbox switch --agent pi` works
- `cli/run-tests.bash` passes

**Dependencies:** m11.3 (templates must exist for init/switch to work)

**Risks:** None — mechanical addition to existing lists.

### m11.5-build-and-ci

**Summary:** Add Pi to build.sh and CI workflows.

**Scope:**
- Add `PI_VERSION`, `PI_EXTRA_PACKAGES` defaults, `build_pi()` function, case entries in `images/build.sh`
- Add `PI_IMAGE_NAME` env var, `build-pi` job in `.github/workflows/build-images.yml`
- Create `.github/workflows/check-pi-version.yml` (daily cron, npm version check)
- Add Pi to summary job in build-images.yml

**Acceptance Criteria:**
- `./images/build.sh pi` builds the Pi image
- `./images/build.sh all` includes Pi
- CI workflow YAML is valid (no syntax errors)
- Version check workflow follows existing pattern

**Dependencies:** m11.1 (Dockerfile must exist for build to work)

**Risks:** None — follows established CI pattern. Pick a unique cron slot (e.g., 11am UTC).

### m11.6-docs-and-readme

**Summary:** Add Pi agent documentation and update the project README.

**Scope:**
- Create `docs/agents/pi.md` with setup, auth, and usage instructions
- Document that Pi is provider-agnostic: users must add the appropriate provider service to their policy
- Update `README.md` supported agents table with Pi row
- Update `docs/plan/project.md` to mark m11 as done (after all tasks complete)

**Acceptance Criteria:**
- `docs/agents/pi.md` covers authentication (API key and OAuth), usage, and provider policy setup
- README table includes Pi with correct status indicators
- Links are valid

**Dependencies:** All other tasks (docs describe the finished feature)

**Risks:** None.

## Execution Order

1. **m11.1** (Dockerfile) and **m11.2** (proxy) and **m11.3** (templates) — all independent, can be done in parallel
2. **m11.4** (CLI integration) — after m11.3
3. **m11.5** (build + CI) — after m11.1
4. **m11.6** (docs) — after everything else

Critical path: m11.3 -> m11.4 (CLI needs templates to exist).

## Risks

- **Provider-agnostic complexity**: Unlike other agents that always talk to one API, Pi users choose their provider at runtime. The documentation must clearly explain that the `pi` service only covers Pi infrastructure and users need to add provider-specific services. Mitigation: clear docs and a note in the agent.yml template comments.
- **No auto-approve flag**: Pi has no permission system, so there's no `--dangerously-skip-permissions` equivalent. This simplifies the sandbox story (Pi already runs in yolo mode) but may confuse users expecting a flag. Mitigation: document this in pi.md.

## Definition of Done

- `agentbox init --agent pi` works in both CLI and devcontainer modes
- Pi image builds locally and via CI
- Proxy allows Pi-specific domains and blocks everything else
- `agentbox switch --agent pi` works
- All existing CLI tests pass with Pi added
- Version-check workflow detects new Pi releases
- Documentation covers setup, auth, and provider policy configuration

## Changes

(None yet)
