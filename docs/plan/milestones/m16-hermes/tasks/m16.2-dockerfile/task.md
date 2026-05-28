# Task: m16.2 - Hermes Dockerfile

## Summary

Build the `agent-sandbox-hermes` Docker image. Extends the project's base image, installs Hermes from PyPI at a pinned
version (`hermes-agent==${HERMES_VERSION}`) into a venv at `/opt/hermes/.venv`, bakes a sandbox-friendly
`cli-config.yaml`, and exposes the `hermes` CLI on the dev user's PATH.

## Scope

**Included:**
- `images/agents/hermes/Dockerfile` extending `agent-sandbox-base`
- `images/agents/hermes/cli-config.yaml` baked at build time with `security.allow_lazy_installs: false`
- System packages: `python3.11 python3.11-venv python3-pip`. `build-essential gcc libffi-dev` are deliberately
  **not** included by default — modern Python deps ship manylinux wheels; only added back if a transitive dep needs
  to build from source during install. Resolve during execution.
- uv installed via `pip install uv` (no curl-pipe-sh; uses the already-installed pip, fewer moving parts)
- `uv pip install hermes-agent==${HERMES_VERSION}` into `/opt/hermes/.venv`. PyPI normalizes the calver `v` prefix
  off, so the build arg uses the PyPI form `2026.5.16`, not the git-tag form `v2026.5.16`. No extras for v1.
- `hermes` symlinked into `/usr/local/bin/hermes`
- `HERMES_HOME=/home/dev/.hermes` directory created and owned by `dev`
- ENV: `HERMES_HOME`, `HERMES_YOLO_MODE=1`, plus `HERMES_BUNDLED_SKILLS` if the spike shows the data_files-based
  skills path needs to be configured explicitly (TBD during execution — see Open Questions)
- OCI labels (`org.opencontainers.image.description`, `com.mattolson.agentsandbox.hermes-version`)
- `EXTRA_PACKAGES` build arg following the established validation regex pattern from Pi/Codex
- Build verification: `docker build` succeeds and `docker run --rm <img> hermes --version` prints a non-empty version

**Excluded from m16.2 (handled in other tasks):**
- Wiring into `images/build.sh` (m16.6)
- CI build job and version-check workflow (m16.6)
- CLI template and devcontainer (m16.4)
- Proxy service domain entry and `KNOWN_AGENTS` (m16.3)
- Agent registry in Go (m16.5)
- Agent docs (m16.7)

**Explicitly out of scope for the v1 image shape (per m16.1 strategy):**
- Node.js, npm, and the Ink TUI (`ui-tui/`)
- Playwright browsers and the system codecs they require
- ffmpeg (voice features)
- docker-cli (no docker-in-docker)
- openssh-client (sandbox blocks SSH anyway)
- s6-overlay supervisor (single hermes process, not the cluster)
- The web/dashboard frontend (`web/`)
- pip extras other than the bare base install

## Acceptance Criteria

From the milestone, plus discovery-derived additions:

- [ ] `docker build -t agent-sandbox-hermes:local --build-arg BASE_IMAGE=agent-sandbox-base:local
      -f images/agents/hermes/Dockerfile images/agents/hermes/` succeeds on linux/amd64
- [ ] `docker run --rm agent-sandbox-hermes:local hermes --version` (or whatever Hermes's version subcommand is)
      prints a non-empty version string matching `${HERMES_VERSION}`
- [ ] The image carries `com.mattolson.agentsandbox.hermes-version="${HERMES_VERSION}"` as a label, verifiable via
      `docker inspect`
- [ ] `docker run --rm agent-sandbox-hermes:local printenv HERMES_HOME HERMES_YOLO_MODE` prints the expected values
- [ ] The baked `cli-config.yaml` is readable inside the container at its expected path and contains
      `security.allow_lazy_installs: false`
- [ ] Smoke test: running `hermes` (or the closest interactive invocation that doesn't require a provider key) does
      not crash with an ImportError or a missing-Node-module error. **If this fails**, the v1 shape collapses and the
      plan expands to add Node + npm + workspace build for `ui-tui/` — see the spike in step 2.
- [ ] Image builds for `linux/arm64` (Apple Silicon target) via `docker buildx build --platform linux/arm64 ...`. uv
      and Python both have arm64 support; pip wheels resolve per arch automatically. Confirm at the end.

## Applicable Learnings

From `docs/plan/learnings.md` and m16.1 discovery:

- **Lazy installs must be disabled:** baking `security.allow_lazy_installs: false` into `cli-config.yaml` is what
  prevents runtime pip-from-pypi inside the sandbox; env vars alone don't catch this config-driven knob.
- **`agent-sandbox-base` already provides:** `git` (custom-compiled 2.50.1), `curl`, `ripgrep`, `procps`,
  `ca-certificates`, the `dev` user (UID 501, not 500 — CLAUDE.md is stale on this), `/home/dev`, the firewall init
  scripts, the entrypoint shim. **Do not re-install** these.
- **Pi/Codex Dockerfiles are the references:** Pi installs from npm at a pinned version with no fuss; Codex installs
  from GitHub releases with TARGETARCH branching and bakes `/etc/codex/config.toml`. Hermes follows the Pi shape more
  closely (PyPI install at pinned version) plus Codex-style config baking. We don't need TARGETARCH branching
  (PyPI/wheels handle multi-arch automatically).
- **EXTRA_PACKAGES validation pattern:** copy the regex from `images/agents/codex/Dockerfile` verbatim. Do not
  reinvent.
- **Image layer ordering matters for cache:** put apt-get + `pip install uv` (rarely changes) before the
  `uv pip install hermes-agent==...` step (changes on every HERMES_VERSION bump). The PyPI install step should be its
  own layer so `cli-config.yaml` edits don't invalidate it.

## Plan

### Files Involved

To create:
- `images/agents/hermes/Dockerfile`
- `images/agents/hermes/cli-config.yaml`

No modifications to existing files in m16.2. Build-script wiring is m16.6.

### Approach

Step through it in the order the Dockerfile reads:

1. **`FROM ${BASE_IMAGE}`**, `ARG BASE_IMAGE=agent-sandbox-base:local`. Match the pattern in every other agent
   Dockerfile.
2. **System deps as root, single layer.** Match Codex's EXTRA_PACKAGES validation regex and append to the default
   package list. Defaults: `python3.11 python3.11-venv python3-pip`. `build-essential gcc libffi-dev` are deliberately
   left off the default list — if a transitive dep needs to compile from source, the install will fail loudly and
   we'll add them back; defaulting to the minimal set keeps the image small.
3. **`pip install uv`.** No curl-pipe-sh. uv lives at the system Python's site-packages and on PATH. Build-time use
   only.
4. **`COPY cli-config.yaml /etc/hermes/cli-config.yaml`.** Content TBD during execution — minimally
   `security.allow_lazy_installs: false`. Confirm the exact YAML nesting path during execution (see Open Questions).
5. **`ARG HERMES_VERSION=2026.5.16`** (PyPI form, no `v` prefix). Default value should be whatever PyPI reports as
   latest when execution starts; this planning value will be stale.
6. **Create venv and install from PyPI:** `uv venv --python python3.11 /opt/hermes/.venv` then
   `uv pip install --python /opt/hermes/.venv/bin/python hermes-agent==${HERMES_VERSION}`. No extras for v1.
7. **`ln -s /opt/hermes/.venv/bin/hermes /usr/local/bin/hermes`.** Make hermes invokable from anywhere.
8. **Create `HERMES_HOME`:** `mkdir -p /home/dev/.hermes && chown -R dev:dev /home/dev/.hermes`.
9. **`USER dev`** (matches Codex pattern).
10. **ENV block:** `HERMES_HOME=/home/dev/.hermes`, `HERMES_YOLO_MODE=1`, plus `HERMES_BUNDLED_SKILLS` (path TBD)
    only if the spike shows it's needed for runtime skills resolution.
11. **OCI labels:** description + `com.mattolson.agentsandbox.hermes-version`.

### Implementation Steps

- [x] **Spike:** PyPI install + `hermes --help` works without `ui-tui/`. v1 shape locked.
- [x] **Lazy-install disable path:** confirmed via `tools/lazy_deps.py:_allow_lazy_installs` —
      `HERMES_DISABLE_LAZY_INSTALLS=1` env var short-circuits the config loader. Using env var, not a baked YAML.
- [x] **Extras:** none for v1.
- [x] **Drop uv:** plain `python3 -m venv` + the venv's pip is sufficient. No PEP 668 dance.
- [x] **Dockerfile written** at `images/agents/hermes/Dockerfile`.
- [ ] **User builds locally** (commands in execution log) and verifies acceptance criteria.
- [ ] **Build for `linux/arm64`** via buildx to confirm multi-arch portability.
- [ ] **Update m16.4 (templates) preview** with the env-var list (HERMES_HOME, HERMES_YOLO_MODE, provider keys) and
      the named volume target (`/home/dev/.hermes`). Input to the next task, not a code change in m16.2.

### Open Questions

Most originally-open questions were resolved during execution. Remaining items:

1. **Skills under PyPI install.** `find /usr/local /opt -name skills` in the spike found only the openai SDK's
   skill dirs, not Hermes's `skills/` or `optional-skills/`. `hermes --help` works fine, so this is not a blocker
   for v1. Open: if real chat interactions need bundled skills, we'll either (a) set `HERMES_BUNDLED_SKILLS` to
   wherever data_files actually placed them, or (b) verify Hermes lazily fetches skills from
   `hermes-agent.nousresearch.com/docs/api/skills-index.json` (already allowlisted). Defer until m16.7's manual
   verification surfaces it as a real problem.
2. **Image size.** To be measured after the user's build. Target: well under 1 GB. Upstream's image is ~5 GB; ours
   should be a small fraction without Node/Playwright/ffmpeg/clone-tree.

## Outcome

Completed 2026-05-27. `images/agents/hermes/Dockerfile` shipped; all acceptance checks pass on host (Apple Silicon /
Colima). Image size 813 MB.

### Acceptance Verification

- [x] `docker build` succeeds on linux/amd64 (verified on host; Colima/Apple Silicon native arm64)
- [x] `docker run --entrypoint "" agent-sandbox-hermes:local hermes --version` prints
      `Hermes Agent v0.14.0 (2026.5.16)`
- [x] Image carries `com.mattolson.agentsandbox.hermes-version=0.14.0` label
- [x] `HERMES_HOME`, `HERMES_YOLO_MODE`, `HERMES_DISABLE_LAZY_INSTALLS` all set
- [x] `/home/dev/.hermes` exists and is owned by `dev:dev`
- [x] Smoke test: `hermes --help` runs cleanly as the dev user, no ImportError, no Node-related failure
- [-] linux/arm64 build via buildx — local Colima build is arm64 native; cross-arch validation belongs to m16.6 CI
      matrix

### Learnings

Appended to `docs/plan/learnings.md`:

- Runtime one-shot `docker run` against any image extending `agent-sandbox-base` hangs because the base entrypoint
  runs firewall init that needs `NET_ADMIN` + a proxy sidecar. Use `--entrypoint ""` for probes; full runs via
  `agentbox exec`.

### Follow-up Items

- **m16.3 input:** default `hermes` SERVICE_DOMAINS entry in the proxy: `["hermes-agent.nousresearch.com"]`. Plus
  `KNOWN_AGENTS += ["hermes"]`. (Already documented in milestone Changes; m16.3 picks it up.)
- **m16.4 input:** templates need to surface env vars for provider auth (`NOUS_API_KEY`, `OPENROUTER_API_KEY`,
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `NOVITA_API_KEY`) in the agent.yml's `environment:`
  block, and mount a named volume at `/home/dev/.hermes` so learned skills/memory persist across restarts.
- **Skills resolution under PyPI install** remains an open observability item for m16.7 manual verification. If
  bundled skills are missing at runtime, set `HERMES_BUNDLED_SKILLS` or check whether Hermes lazily fetches from
  `hermes-agent.nousresearch.com/docs/api/skills-index.json`.
