# Hermes Discovery Findings

**Source:** [github.com/NousResearch/hermes-agent](https://github.com/nousresearch/hermes-agent)
**Pinned commit:** `cea87d9139044870752aafdcdf9ca253049ae175` (the HEAD of `main` at clone time, 2026-05-25)
**Latest visible release tag:** `v2026.5.16` (commit `8487dfb`)
**Date of discovery:** 2026-05-25

Findings are pinned to the commit SHA above so the rest of m16 can be implemented against the same upstream state.
If m16.2+ executes weeks later and any answer below has changed upstream, re-verify before treating it as current.

## Q1 - Binary layout

Hermes is a **Python application**, not a single compiled binary.

- Primary language: Python 3.11+ (1,901 `.py` files in the repo)
- Dependency manager: **uv** (`pyproject.toml` + `uv.lock`)
- Entry point: `hermes_cli/main:main` (the `hermes` shell script at the repo root is a thin Python wrapper)
- Installs via uv into a venv (upstream image uses `/opt/hermes/.venv`)
- Adjacent stack:
  - **Node.js / npm** — `web/`, `ui-tui/` (Ink-based TUI), and `package.json` workspaces
  - **Playwright** — bundled browsers for browser-automation skills (optional but bundled)
  - **Optional supervisor** — upstream image uses s6-overlay to supervise main hermes + dashboard + per-profile gateways

Four install paths exist upstream, in increasing weight/parity:

1. **PyPI distribution.** Published as `hermes-agent` via `.github/workflows/upload_to_pypi.yml`, which triggers on
   every calver tag push (`v20*`). `[all]` extra exists at `pyproject.toml:174`; per-feature extras include
   `anthropic`, `firecrawl`, `messaging`, `voice`, `mcp`, `honcho`, `matrix`, `slack`, etc. `setup.py:data_files`
   grafts `skills/` and `optional-skills/` into the wheel. Excludes `ui-tui/` (Node/Ink TUI, npm workspace) and
   `web/` (built JS dashboard) — those are not packaged for PyPI.
2. **Upstream Docker image.** `nousresearch/hermes-agent` on Docker Hub, built by
   `.github/workflows/docker-publish.yml` on every `main` push and on releases. Image is ~5 GB and runs an s6-overlay
   supervisor over main hermes + dashboard + per-profile gateways.
3. **`setup-hermes.sh`** (18 KB, repo root) — developer-oriented installer; clone + `uv pip install -e .` from local
   source.
4. **`scripts/install.sh`** (82 KB) — the curl-piped installer linked from the public docs page; does desktop
   integration, interactive prompts, OS detection, and fallbacks. Defaults to `main`. Not appropriate for our image
   build path (opaque, interactive, oriented at end-user workstations).

System packages the upstream Dockerfile installs (Debian 13.4) for path 2:
`build-essential curl nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git openssh-client
docker-cli xz-utils`. This is heavier than Pi/OpenCode/Factory (which are pure npm installs over Node).

**Recommended strategy for m16.2:** path 3 in a stripped form — `git clone --depth 1 --branch ${HERMES_VERSION}` then
`uv pip install -e ".[<chosen-extras>]"` in our base image. Replicate the core pieces, do not curl-pipe `install.sh`.
Skip Node/npm (no Ink TUI), Playwright (no browser skills), ffmpeg (no voice), and the s6-overlay supervisor for v1
— the minimum viable system-deps set is roughly `python3.11 python3.11-venv python3.11-dev build-essential gcc
libffi-dev git ripgrep` plus a uv binary install. Verify in m16.2 that the plain CLI (`HERMES_TUI=0` /
`HERMES_NONINTERACTIVE=1`) is functional without the Ink TUI before locking the shape.

PyPI install (path 1) was considered and deferred: the wheel omits `ui-tui/` and `web/`, but if the v1 sandbox CLI
turns out to be fine without those, a future revision could switch from clone-install to
`uv pip install hermes-agent[<extras>]==<version>` for a much simpler Dockerfile.

## Q2 - Versioning

Upstream **does publish release tags**, in **calver** format `v2026.M.D`.

Recent tags visible (verified via `git ls-remote --tags`):
- `v2026.5.16` (latest)
- `v2026.5.7`
- `v2026.4.30`
- `v2026.4.8`
- `v2026.4.3`

**Pinning strategy for `HERMES_VERSION`:** use a release tag. The Dockerfile clones at `--branch v2026.M.D --depth 1`
and `uv pip install -e .` from there.

**Version-check workflow shape:** hit `https://pypi.org/pypi/hermes-agent/json` and read `.info.version`. This is the
same endpoint Hermes uses for its own update check (`hermes_cli/banner.py:_fetch_pypi_latest`), and it returns the
latest published version directly without a GitHub token or release-asset parsing. PyPI tracks calver because the
publish workflow triggers on calver tag push, so the PyPI version mirrors the git tag we want to clone.

Small acceptable drift: PyPI publish runs after a tag is pushed, so for a few minutes after a release the tag exists
but PyPI still reports the prior version. The version-check workflow lags by that window; not worth designing around.

The `npm view` shape used by Pi/OpenCode does not apply.

**Note on update-check at startup:** Hermes itself runs a startup update check (`hermes_cli/banner.py:402
prefetch_update_check`) that hits `https://github.com/NousResearch/hermes-agent.git` and
`https://github.com/NousResearch/hermes-agent/releases/tag`. No env var to disable was found. Add the upstream repo to
the existing github service entry to keep this non-noisy in-sandbox.

## Q3 - Auth env vars

Hermes reads provider keys via env (also supports `cli-config.yaml`). The env vars actually consumed in source (not
just commented in `.env.example`):

**Nous Research (primary provider):**
- `NOUS_API_KEY`
- `NOUS_BASE_URL`, `NOUS_INFERENCE_BASE_URL`, `NOUS_PORTAL_BASE_URL`

**Other providers (one of these required if not using Nous):**
- `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`
- `OPENAI_API_KEY`, `OPENAI_BASE_URL` (alt: `OPENAI_API_BASE`), `OPENAI_ORG_ID`
- `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`
- `GEMINI_API_KEY`, `GEMINI_BASE_URL`, `GOOGLE_API_KEY`
- `NOVITA_API_KEY`, `NOVITA_BASE_URL`
- `OLLAMA_API_KEY` (local)

**Hermes-internal (not provider auth):**
- `HERMES_API_KEY` — gateway/server auth between hermes processes, not a provider key
- `HERMES_INFERENCE_PROVIDER` — selects which provider is active
- `HERMES_INFERENCE_MODEL` — model identifier

**Optional integrations (off by default unless keys set):**
- Langfuse observability: `HERMES_LANGFUSE_PUBLIC_KEY`, `HERMES_LANGFUSE_SECRET_KEY`, `HERMES_LANGFUSE_BASE_URL`
- Honcho memory: `HONCHO_API_KEY`
- Home Assistant: `HASS_TOKEN`
- Many platform-adapter tokens (Telegram, Discord, etc.) — out of scope for CLI sandbox

There are 200+ `HERMES_*` env vars total; most are runtime tuning knobs (timeouts, buffer sizes, batch delays per
platform) that the milestone doesn't need to surface.

## Q4 - Infrastructure domains

Hardcoded Nous-side hostnames found in Python source:

| Domain | Purpose | Required? |
|---|---|---|
| `hermes-agent.nousresearch.com` | Docs site, plus `/docs/api/model-catalog.json` and `/docs/api/skills-index.json` | Yes — model catalog and skills index fetched at startup/skill operations |
| `inference-api.nousresearch.com` | Nous-hosted inference API | Only if Nous Portal is the active provider |
| `firecrawl-gateway.nousresearch.com` | Nous-hosted Firecrawl gateway for web scraping | Only if the firecrawl skill is used |
| `chat.nousresearch.com` | Community chat (Nous portal UI) | No — referenced for navigation links only |

Plus startup-check endpoints (covered in Q7):
- `github.com/NousResearch/hermes-agent` (update check)
- `api.github.com/repos/NousResearch/hermes-agent/...` (releases query, skills hub)

Plus optional opt-in services (off by default):
- `app.honcho.dev` — Honcho memory provider (only if `HONCHO_API_KEY` set)
- `cloud.langfuse.com` — Langfuse observability (only if `HERMES_LANGFUSE_*` keys set)
- `pypi.org` — lazy installs (see Q7); should be disabled in sandbox

**Default `hermes` SERVICE_DOMAINS for the proxy:**

```python
"hermes": ["hermes-agent.nousresearch.com"]
```

Users who pick Nous Portal as their provider add `inference-api.nousresearch.com` via their own policy (parallel to how
Pi/OpenCode users add their chosen provider service). Document this in `docs/agents/hermes.md`.

## Q5 - State directory

- Primary env var: `HERMES_HOME`
- Default if unset: `~/.hermes` (resolved via `os.path.expanduser`)
- Upstream Docker image sets: `HERMES_HOME=/opt/data` (the `hermes` user's home, on a `VOLUME`)
- Contents: `.env`, `skills/`, `cache/`, profile configs, learned skill state, persona/memory, gateway tokens, image
  cache (`cache/images/`)

**Recommendation for m16.4 template:**
- Set `HERMES_HOME=/home/dev/.hermes` (or accept default since `$HOME` is already `/home/dev` for the dev user)
- Mount a named volume `hermes-state` at `/home/dev/.hermes` so learned skills survive `agentbox down && up`
- Also mount `hermes-history` at the equivalent of `~/.zsh_history` per the existing convention

## Q6 - Sandbox / yolo flag

- `HERMES_YOLO_MODE=1` enables unattended execution (skips shell-exec confirmation prompts)
- Any truthy value works (`is_truthy_value` parses common forms)
- Can also be toggled at runtime via TUI command, but the env var is the persistent default
- Related: `HERMES_ACCEPT_HOOKS`, `HERMES_NONINTERACTIVE`, `HERMES_EXEC_ASK` — finer-grained toggles for specific
  classes of action

**Recommendation for m16.4 template:** set `HERMES_YOLO_MODE=1` in the compose env. Document the trade-off in
`docs/agents/hermes.md`.

## Q7 - Startup network behavior

Network calls that happen at or near startup, in order of attention:

1. **Update check** — `hermes_cli/banner.py:prefetch_update_check` hits
   `https://github.com/NousResearch/hermes-agent.git` and the GitHub releases page. No env var disable found.
   **Mitigation:** the existing user policy already allowlists `nousresearch/hermes-agent` (after the case-sensitivity
   workaround); the check will succeed silently. No code change needed.

2. **Lazy installs (pip)** — `security.allow_lazy_installs` flag in `cli-config.yaml`, default **`true`**. When the
   agent encounters a missing Python dep (e.g., `python-telegram-bot`, `azure-identity`), it pip-installs on demand
   from `pypi.org`. This is **important to disable in a sandbox** — pypi.org is not in the default allowlist, and
   silent runtime pip installs would create a moving target inside the container.
   **Mitigation for m16.2:** bake `security.allow_lazy_installs: false` into a default `cli-config.yaml` in
   `/opt/hermes` (or the equivalent path), and document the trade-off (some adapters will refuse to start instead of
   self-installing).

3. **Model catalog fetch** — `hermes-agent.nousresearch.com/docs/api/model-catalog.json` is fetched when the model
   picker runs. Allowed by the recommended default service domain.

4. **Skills index fetch** — `hermes-agent.nousresearch.com/docs/api/skills-index.json` is fetched on skill ops. Same
   allowlist.

5. **Skills hub** — `api.github.com/repos/NousResearch/hermes-agent/...` for fork/PR operations. Triggered only by
   explicit user command, not at startup. The existing user policy already covers GitHub git access but **not**
   `api.github.com`; users who want skill PR sharing need to add `api.github.com` to their policy or use the m18
   GitHub REST wrapper once it lands.

6. **Telemetry (Langfuse)** — opt-in. No baked-in keys; safe by default.

7. **Honcho memory** — opt-in. No baked-in keys; safe by default.

8. **Playwright browser downloads** — `PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright` in upstream Dockerfile;
   browsers installed at build time, not runtime. If we replicate the build, no runtime browser fetch happens.

## Implications for downstream tasks

These should be folded into the milestone plan if they materially change scope:

- **m16.2 (Dockerfile)**: clone at `--branch ${HERMES_VERSION}`, then `uv pip install -e ".[<extras>]"` in our base
  image. Replicate; do not curl-pipe `scripts/install.sh`. Strip upstream's image down: drop Node/npm (skip Ink TUI
  for v1), Playwright (skip browser skills), ffmpeg (skip voice), docker-cli, openssh-client, and the s6-overlay
  supervisor (single hermes process, not the cluster). Minimum system deps roughly
  `python3.11 python3.11-venv python3.11-dev build-essential gcc libffi-dev git ripgrep` plus a uv binary install.
  Bake `security.allow_lazy_installs: false` into a default `cli-config.yaml`. **Spike during m16.2:** verify the
  plain CLI is functional without the Ink TUI before locking the shape; if not, add Node + workspace build back.
- **m16.3 (proxy)**: default `hermes` service is just `["hermes-agent.nousresearch.com"]`. Document that Nous Portal
  users also need `inference-api.nousresearch.com`, Firecrawl users need `firecrawl-gateway.nousresearch.com`, and
  skills-hub users need `api.github.com`. None of these are added by the default service entry.
- **m16.4 (templates)**: `HERMES_HOME=/home/dev/.hermes` (or default) with a named volume. `HERMES_YOLO_MODE=1` in the
  env. Surface provider env vars in the agent.yml's `environment:` block so users can pass them through.
- **m16.6 (build + CI)**: version-check workflow queries `https://pypi.org/pypi/hermes-agent/json` and reads
  `.info.version`. Anonymous read, no GitHub token. Same endpoint Hermes itself uses for its own update check. Pick
  cron slot 13:00 UTC. Accept a few-minute lag between tag push and PyPI publish.
- **m16.7 (docs + verify)**: doc the case-sensitivity workaround for repo allowlists until the m14 follow-up lands;
  doc the lazy-installs disable; doc which Nous and provider domains to add per provider choice; restart-persistence
  test for `$HERMES_HOME`.

## Open questions still unresolved

- **Does the plain CLI work without the Ink TUI?** The env vars (`HERMES_TUI=0`, `HERMES_NONINTERACTIVE=1`) suggest
  yes, but it has not been runtime-verified. This is the v1-shape gating question for m16.2 — if the answer is no,
  add Node + workspace build back into the Dockerfile.
- **What does `security.allow_lazy_installs: false` actually break at runtime?** The lazy-install path covers
  azure-identity, python-telegram-bot, Honcho, and others. For CLI-only use without those adapters, disabling is
  safe; document and accept.
- **Multi-arch:** upstream's Dockerfile supports amd64 and arm64 via TARGETARCH. Need to confirm our build pipeline
  passes through correctly for the Apple Silicon target.
