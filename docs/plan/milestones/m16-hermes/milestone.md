# Milestone: m16 - Hermes Agent Support

## Goal

Add [Hermes](https://hermes-agent.nousresearch.com/docs/) (Nous Research's self-improving agent) as a supported agent
in Agent Sandbox. Users can initialize, run, and switch to Hermes via the standard `agentbox` workflow.

## Scope

**Included:**
- Hermes agent Docker image extending the base image, installed from upstream's shell installer at a pinned version
- CLI templates (compose layer, devcontainer) modeled on the existing provider-agnostic agents (Pi, OpenCode)
- CLI agent registry update in `internal/runtime/agents.go` and Go test updates
- Proxy service entry for Hermes infrastructure domains and `hermes` in `KNOWN_AGENTS`
- `images/build.sh` support, build job in `build-images.yml`, daily version-check workflow
- Agent documentation (`docs/agents/hermes.md`) and README support-matrix update

**Excluded:**
- Hermes's non-CLI adapters (Telegram, Discord, Slack, WhatsApp, Signal, Matrix, Mattermost, Email, SMS, DingTalk,
  Feishu, WeCom, Weixin, QQ Bot, Yuanbao, BlueBubbles, Home Assistant, Microsoft Teams, Google Chat). Hermes ships 20+
  platform integrations; the sandbox only covers the CLI.
- Provider-specific proxy domains. Hermes is provider-agnostic (Nous Portal, OpenRouter, OpenAI, or any endpoint); users
  add the relevant provider service (`claude`, `codex`, `openai`, `gemini`, `openrouter`) to their policy themselves.
- Hermes's self-improving "skills" persistence semantics beyond mounting the appropriate state volume so learned skills
  survive container restarts.
- Proxy-side credential injection for any provider Hermes calls. That work belongs to m17 (provider API-key injection)
  and is not gated on this milestone.

## Applicable Learnings

- The add-agent skill provides a comprehensive checklist for new agent integrations; follow it closely.
- Policy layering via Dockerfile COPY overwrites the parent layer's policy cleanly.
- Provider-agnostic agents must document clearly that the agent service only covers agent infrastructure; users must add
  a separate provider service to their policy. Pi and OpenCode set the pattern.
- Daily version-check workflows pick unique cron slots to avoid CI contention (Pi is 11:00 UTC, OpenCode is 12:00 UTC);
  pick the next unused hour.
- For agents installed via shell installers that pull from `main`, derive a stable version anchor (release tag or commit
  SHA) at build time and bake it into the image label, or the version-check workflow has nothing meaningful to compare
  against.

## Tasks

### m16.1-discovery

**Summary:** Resolve the open questions about Hermes that the public docs do not answer, so subsequent tasks can be
implemented against known specifics rather than guesses.

**Scope:**
- Inspect `https://github.com/NousResearch/hermes-agent`, the install script, and any embedded help text to determine:
  - The actual binary or runtime layout the shell installer produces
  - Whether the upstream publishes versioned releases or only tracks `main`; identify the strategy for pinning a
    specific version at image build time
  - Authentication mechanism and the env var names Hermes reads (e.g., `NOUS_API_KEY`, `OPENROUTER_API_KEY`,
    `OPENAI_API_KEY`, custom)
  - Hermes infrastructure domains the CLI contacts directly (model registry, learning loop, telemetry, update checks)
    distinct from the provider endpoints
  - Hermes's state directory layout (where learned skills, persona, and session memory are written), so the right volume
    mount can be defined
  - Whether Hermes has an internal sandboxing or shell-exec confirmation flag that must be disabled in-container
    (analogous to OpenAI Codex's `--sandbox-mode none` or OpenCode's permissions config)
  - Whether Hermes does auto-update or LSP downloads at startup that need disabling (OpenCode required
    `OPENCODE_DISABLE_AUTOUPDATE` and `OPENCODE_DISABLE_LSP_DOWNLOAD`)
- Capture findings in a short discovery note under this milestone folder, with citations to source files in the upstream
  repo. The note feeds m16.2-m16.4 and m16.7.

**Acceptance Criteria:**
- A discovery note exists under `docs/plan/milestones/m16-hermes/` listing each open question and its resolution (or
  "not applicable, here is why").
- The note names the specific env vars, domains, state paths, and feature flags that downstream tasks will use.

**Dependencies:** None.

**Risks:** Upstream may not publish versioned releases. If only `main` is available, this milestone must decide between
pinning a commit SHA (reproducible but manual updates), tracking `main` with the version-check workflow watching commit
SHAs, or asking upstream to tag releases. The decision goes in the discovery note.

### m16.2-dockerfile

**Summary:** Build the agent-sandbox-hermes Docker image.

**Scope:**
- `images/agents/hermes/Dockerfile` extending the base image
- Install Hermes via its upstream installer at the pinned version chosen in m16.1, not `main`
- `HERMES_VERSION` build arg with a default matching the pinned version, image labels (`org.opencontainers.image.version`,
  agent-specific metadata)
- Create whatever state directory m16.1 identifies, owned by the `dev` user
- Apply any sandbox-friendly defaults discovered in m16.1 (auto-update disable, permission overrides, etc.)
- Standard `EXTRA_PACKAGES` build arg and `USER root` → `USER dev` transitions following existing Dockerfiles

**Acceptance Criteria:**
- `./images/build.sh hermes` produces an image locally.
- `docker run --rm agent-sandbox-hermes:local hermes --version` (or whatever Hermes's version command is, per m16.1)
  prints the pinned version.
- The image carries an OCI version label that matches the pinned version.

**Dependencies:** m16.1 (need the install mechanism, version pinning strategy, and any required runtime flags).

**Risks:** A shell-installer-only upstream is harder to reproduce than `npm install <pkg>@<version>`. If the installer
fetches `main` unconditionally, the Dockerfile may have to clone the repo at a specific ref and run the installer
locally rather than from the curl-piped URL.

### m16.3-proxy-domains

**Summary:** Register Hermes in the proxy as a known agent and add its infrastructure service domains.

**Scope:**
- Add `"hermes"` entry to `SERVICE_DOMAINS` in `images/proxy/addons/enforcer.py` with the domains identified in m16.1
- Add `"hermes"` to `KNOWN_AGENTS` in `images/proxy/render-policy`
- If discovery shows Hermes has no infrastructure domains of its own (purely a thin client over user-chosen providers),
  the hermes service may be defined with an empty domain list, matching the Pi pattern
- Add a brief comment in the proxy code or in `docs/agents/hermes.md` explaining that provider domains are user-managed

**Acceptance Criteria:**
- Proxy starts with `AGENTBOX_ACTIVE_AGENT=hermes` without error.
- Existing proxy Python unit tests still pass.
- Policy rendering for `hermes` produces the expected merged host records.

**Dependencies:** m16.1 (needs the list of Hermes infrastructure domains).

**Risks:** Hermes's "self-improving" learning loop may push or pull from a Nous Research endpoint at runtime. If that
endpoint is mandatory, blocking it would break the agent's core differentiator. m16.1 must enumerate this and the
default service list must reflect what Hermes actually requires.

### m16.4-templates

**Summary:** Add the CLI compose layer and devcontainer templates for Hermes.

**Scope:**
- `internal/embeddata/templates/hermes/cli/agent.yml` — image ref, named volume(s) for whatever state paths m16.1
  identifies, environment-variable surface for the auth env vars Hermes uses
- `internal/embeddata/templates/hermes/devcontainer/devcontainer.json` — layered compose refs, no VS Code extensions
  (CLI-only agent), JetBrains proxy settings to match the existing pattern

**Acceptance Criteria:**
- `agentbox init --agent hermes --mode cli` generates a valid compose stack.
- `agentbox init --agent hermes --mode devcontainer` generates a valid devcontainer config.
- `docker compose config` on the generated stack resolves without errors.

**Dependencies:** m16.1 (state path layout, env-var surface).

**Risks:** Hermes's persistent "skills" learning means the state volume must cover the right path. Mounting the wrong
path silently drops learned state across restarts; this should be verified end-to-end in m16.7, not just by config-shape
asserts.

### m16.5-cli-integration

**Summary:** Register Hermes in the Go CLI agent registry and update tests.

**Scope:**
- Append `"hermes"` to `supportedAgents` in `internal/runtime/agents.go`
- Update any Go tests under `internal/` that assert on the agent list, init flows, switch flows, or compose generation
  with the new entry (mirror what was done for Pi and OpenCode)

**Acceptance Criteria:**
- `agentbox init --agent hermes` works end-to-end (driven by integration tests where they exist).
- `agentbox switch --agent hermes` works.
- `go test ./...` passes.

**Dependencies:** m16.4 (templates must exist for init/switch to find them).

**Risks:** None substantive — this is a mechanical addition modeled on prior agent rollouts.

### m16.6-build-and-ci

**Summary:** Wire Hermes into `images/build.sh` and CI workflows.

**Scope:**
- Add `HERMES_VERSION` and `HERMES_EXTRA_PACKAGES` defaults, a `build_hermes()` function, and case entries in
  `images/build.sh`
- Add `HERMES_IMAGE_NAME` env var and a `build-hermes` job in `.github/workflows/build-images.yml`
- Create `.github/workflows/check-hermes-version.yml`, daily cron at the next unused hour after the existing agents
  (Factory 10:00, Pi 11:00, OpenCode 12:00; pick 13:00 UTC unless m16.1 surfaces a reason not to)
- Add Hermes to the summary job in `build-images.yml`
- The version-check workflow must use whatever upstream version source m16.1 settles on (GitHub releases, tags, or commit
  SHAs); `npm view` will not apply

**Acceptance Criteria:**
- `./images/build.sh hermes` and `./images/build.sh all` both build the Hermes image.
- The build-images workflow lints clean (`actionlint` or equivalent if used) and the new job follows the existing
  matrix shape.
- The version-check workflow follows the same trigger-on-update pattern as `check-pi-version.yml`.

**Dependencies:** m16.2 (Dockerfile must exist), m16.1 (version anchor mechanism).

**Risks:** If upstream only publishes `main`, the version-check workflow design will look different from the existing
agents'. m16.1 should choose the shape so this task does not stall mid-implementation.

### m16.7-docs-and-readme

**Summary:** Document Hermes setup and update the project README.

**Scope:**
- Create `docs/agents/hermes.md` covering: install path, authentication (the env vars and provider choices identified in
  m16.1), provider policy setup (which provider services to add depending on Nous Portal vs. OpenRouter vs. OpenAI vs.
  custom), state persistence across restarts, and any sandbox-specific env vars or flags
- **Upgrade path documentation.** `hermes update` is intentionally disabled in the sandbox via `HERMES_MANAGED=AgentSandbox`
  (set in m16.3). The doc must explain (a) why — the venv is read-only and we want reproducible image upgrades, not
  in-place self-updates — and (b) what to do instead: the CI version-check workflow opens a PR bumping `HERMES_VERSION`,
  merge it, image is rebuilt and republished, run `agentbox bump` to pull the new digest, then `agentbox down && agentbox up`.
  Existing `HERMES_HOME` volume persists across the swap. Also call out that `hermes` ships separate user-invoked
  migration subcommands (`hermes gateway migrate-legacy`, `hermes claw migrate`, `hermes setup`) which are NOT triggered
  by upgrade and should be run manually when upstream release notes call out a schema change. `hermes backup` and
  `hermes import` are available for pre-upgrade snapshotting.
- Update `README.md` supported-agents table with a Hermes row
- Mark m16 as done in `docs/plan/project.md` and `docs/roadmap.md`
- End-to-end manual verification: build the image, run `agentbox init --agent hermes`, configure a real provider, run a
  short Hermes session, verify the state volume persists learned skills across `agentbox down && agentbox up`

**Acceptance Criteria:**
- `docs/agents/hermes.md` exists and covers auth, provider policy setup, and state persistence.
- README table includes Hermes with correct status indicators.
- Links are valid.
- The manual verification session described above completes successfully.

**Dependencies:** All prior tasks.

**Risks:** None substantive.

## Execution Order

1. **m16.1** (discovery) first — blocks everything else
2. **m16.2** (Dockerfile), **m16.3** (proxy), **m16.4** (templates) in parallel — independent
3. **m16.5** (CLI integration) — after m16.4
4. **m16.6** (build + CI) — after m16.2
5. **m16.7** (docs + manual verify) — after everything else

Critical path: m16.1 → m16.4 → m16.5 → m16.7.

## Risks

- **Undocumented upstream surface.** Hermes's public docs do not specify auth env vars, API endpoints, state layout, or
  internal sandbox flags. m16.1 is structured to surface these before any code is written; without it, downstream tasks
  would be guesses. If m16.1 cannot answer a question from upstream source, the milestone may have to file an upstream
  issue and pause.
- **Versioning model unknown.** If upstream does not publish releases or tags, the standard `version-check` workflow
  shape (single npm/GitHub-releases query) will not transfer. The discovery task must propose a workable shape (commit
  SHA tracking, release-tag tracking after upstream cooperation, or accepting `main` with an explicit "unstable" label
  on the image).
- **Provider posture confusion.** Like Pi and OpenCode, Hermes can talk to several providers. New users will assume the
  `hermes` service is sufficient. Mitigation: docs must lead with provider policy setup, and the agent.yml template
  comments should call it out at the touch points.
- **Self-improving state.** Hermes claims to persist learned skills and a model of the user across sessions. If the
  state volume mount is wrong, this differentiator silently breaks. Mitigation: m16.7 includes an explicit cross-restart
  verification step rather than relying on config-shape tests alone.

## Definition of Done

- `agentbox init --agent hermes` works in both CLI and devcontainer modes.
- Hermes image builds locally and via CI; daily version-check workflow runs and reports correctly.
- Proxy allows Hermes-specific infrastructure domains (or none, if discovery confirms Hermes has no infrastructure
  domains of its own) and blocks everything else not in the user's policy.
- `agentbox switch --agent hermes` works without losing other agents' state.
- `go test ./...` and the proxy Python test suite both pass with Hermes added.
- `docs/agents/hermes.md`, README support matrix, project plan, and roadmap all reflect m16 as done.
- A manual session confirms Hermes successfully calls at least one provider through the proxy, and learned state
  persists across a container restart.

## Changes

### 2026-05-25: m16.1 discovery complete

Findings recorded in `tasks/m16.1-discovery/discovery.md`, pinned to upstream commit
`cea87d9139044870752aafdcdf9ca253049ae175`. Material updates that affect downstream task scope:

- **Hermes is a Python+uv app, not an npm CLI.** Heavier image footprint than Pi/OpenCode (Python 3.11, uv, Node,
  ripgrep, ffmpeg, Playwright, build tooling). m16.2 scope shifts accordingly; treat upstream's Dockerfile as
  reference, not a literal base. Recommended v1 shape: `uv pip install hermes-agent==${HERMES_VERSION}` from PyPI
  into `/opt/hermes/.venv`, skip Node/Playwright/ffmpeg/docker-cli/s6. Verify (a) the plain CLI works without the
  Ink TUI and (b) PyPI-installed Hermes can find its bundled skills, both as m16.2 spike steps before locking the
  shape.
- **Hermes is published to PyPI** as `hermes-agent` (calver-tagged publish workflow), and **upstream also publishes
  a Docker image** `nousresearch/hermes-agent` on Docker Hub. For m16.2 we use the PyPI install — `ui-tui/` and `web/`
  are omitted from the wheel but v1 skips both anyway; the upstream Docker image (~5 GB, s6-supervised cluster) is
  too heavy and breaks our "extend agent-sandbox-base" convention. Clone-install remains the documented fallback if
  PyPI install proves broken at runtime (skills resolution being the main risk).
- **Upstream publishes calver release tags** (`v2026.M.D`), so `HERMES_VERSION` can pin to a tag. m16.6's
  version-check workflow queries `https://pypi.org/pypi/hermes-agent/json` and reads `.info.version` (same endpoint
  Hermes uses for its own update check). PyPI tracks the calver tag, so the version we check mirrors the tag we'd
  clone. Accept a few-minute lag between tag push and PyPI publish.
- **`security.allow_lazy_installs: false` must be baked** into the image's default `cli-config.yaml`. Otherwise
  Hermes will pip-install Python deps from pypi.org at runtime, which the sandbox does not allow.
- **`HERMES_YOLO_MODE=1`** is the unattended-execution toggle (env var, set in the compose template).
- **`HERMES_HOME` defaults to `~/.hermes`**, used by the upstream-supervised image as `/opt/data`. m16.4 will mount a
  named volume at this path so learned skills persist across restarts.
- **Default `hermes` service in the proxy is just `["hermes-agent.nousresearch.com"]`**. `inference-api.nousresearch.com`,
  `firecrawl-gateway.nousresearch.com`, and `api.github.com` are opt-in per use case and documented in m16.7.

Downstream tasks (m16.2-m16.7) should reference `discovery.md` for concrete env var names, domain lists, state paths,
and feature-flag strings rather than re-deriving them.
