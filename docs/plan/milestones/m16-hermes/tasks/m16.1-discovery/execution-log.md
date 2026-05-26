# Execution Log: m16.1 - Hermes Discovery

## 2026-05-25 - Corrections after user pushback on install strategy

User asked whether `pip install` from PyPI is viable. Re-checked upstream and discovered:

- Hermes IS published to PyPI as `hermes-agent` (`.github/workflows/upload_to_pypi.yml`, triggered by calver tag push).
  Earlier closing summary asserted otherwise without verification — that was a guess presented as fact.
- Upstream also publishes a Docker image: `nousresearch/hermes-agent` on Docker Hub
  (`.github/workflows/docker-publish.yml`). The earlier "did not find evidence in the repo tree" claim missed this
  — the workflow exists; the search pattern (`ghcr.io/.*hermes`) wouldn't have matched Docker Hub.
- `pyproject.toml` has an `[all]` extra plus many per-feature extras (`anthropic`, `firecrawl`, `messaging`, `voice`,
  `mcp`, `honcho`, `matrix`, `slack`, etc.). `setup.py` data_files grafts `skills/` and `optional-skills/` into the
  wheel, so the PyPI distribution is functional for the agent loop. It excludes `ui-tui/` (Ink TUI) and `web/`
  (built dashboard).

**Install-strategy decision (in collaboration with user):**

- For m16.2: clone at `--branch ${HERMES_VERSION}` then `uv pip install -e ".[<extras>]"` in our base image.
  Replicate the core pieces, do not curl-pipe `scripts/install.sh`. Skip Node/npm/Playwright/ffmpeg/docker-cli for v1.
  PyPI install (`uv pip install hermes-agent[extras]==<version>`) deferred — could be simpler, but needs runtime
  verification that the plain CLI works without `ui-tui/`. That verification is an m16.2 spike, not discovery work.
- For m16.6: version check queries `https://pypi.org/pypi/hermes-agent/json` and reads `.info.version`. PyPI and git
  tags are kept in sync by the publish workflow, so the PyPI version mirrors the tag we want to clone. Cleaner than
  the originally proposed `api.github.com/.../releases/latest` shape.

**Decision:** prefer clone-at-tag for install, prefer PyPI for version check. Two different anchors for two different
concerns — install needs the full repo tree (including non-PyPI assets), version check just needs the latest
version string and PyPI gives that with no GitHub token and a simpler endpoint.

**Learning logged:** when claiming "X is not published on Y," verify with a direct query, not by inferring from a
related fact. The earlier "actual Python package isn't on PyPI as a stable distribution" claim should have been
checked against `pyproject.toml` and `.github/workflows/` before being asserted. Cost: zero correctness impact (the
clone-install strategy is what we'd recommend anyway), but it eroded confidence in the discovery doc until corrected.

**discovery.md updated:** Q1, Q2, "Implications", "Open questions" sections all corrected. PyPI and Docker Hub
publishing acknowledged. m16.2 strategy refined with the lean Dockerfile shape. Open-questions section now leads
with the v1-shape gating question ("does the plain CLI work without ui-tui?") rather than the upstream-image
question that was actually answered.

## 2026-05-25 - Discovery complete

Cloned upstream at HEAD `cea87d9139044870752aafdcdf9ca253049ae175`. All seven open questions answered;
findings recorded in `discovery.md`. Highlights:

**Surprises vs. initial milestone assumptions:**
- Hermes is a **Python application managed by uv**, not an npm CLI. The "shell installer" the docs page mentions
  (`scripts/install.sh`) is a bootstrap that clones the repo and runs uv install — the actual Python package isn't on
  PyPI as a stable distribution.
- Upstream **does publish release tags** (calver `v2026.M.D`, latest `v2026.5.16`). This is better than the worst-case
  scenario the milestone risked ("only `main`"). Version-check workflow uses GitHub releases API, not `npm view`.
- The image is **significantly heavier** than Pi/OpenCode: Python 3.11 + uv + Node + ripgrep + ffmpeg + Playwright +
  system build tooling. Upstream's Dockerfile additionally runs s6-overlay supervising main hermes + dashboard +
  per-profile gateways. For the sandbox we should run a single hermes process, not the supervised cluster.
- Hermes has a **runtime lazy-install mechanism** (`security.allow_lazy_installs`, default `true`) that pip-installs
  Python deps on demand. **Must be disabled** in the sandbox or runtime pypi.org access becomes a moving target.
- `HERMES_YOLO_MODE=1` is the standard env var for unattended execution.
- `HERMES_HOME` defaults to `~/.hermes`; the upstream Docker image relocates it to `/opt/data` but that's an upstream
  convention, not a requirement.
- 200+ `HERMES_*` env vars exist; most are tuning knobs irrelevant to sandbox setup.

**Domains feeding the proxy service entry:**
- Default `hermes` service: `["hermes-agent.nousresearch.com"]` (the docs site + JSON model/skills catalogs)
- Opt-in (user policy): `inference-api.nousresearch.com` (Nous Portal), `firecrawl-gateway.nousresearch.com`
  (web-scraping skill), `api.github.com` (skills-hub PR sharing)
- Off by default: `app.honcho.dev` (Honcho memory), `cloud.langfuse.com` (Langfuse observability)

**Process notes:**
- The local-clone strategy was correct. WebFetch was only used early to confirm `raw.githubusercontent.com` was
  reachable; all real extraction came from grep/read on `/tmp/hermes-agent`.
- The case-sensitivity proxy bug surfaced before this task could run — captured in `learnings.md` as an m14
  follow-up. Workaround for now: lowercase repo path in both the policy entry and the clone URL.

**Learning extracted to `docs/plan/learnings.md`:**
- For agents with runtime self-modification behavior (lazy installs, plugin auto-install, model registry fetches),
  the sandbox needs both env-var defaults AND a baked config file that disables those behaviors. Env vars alone won't
  catch a config-driven knob.

**Cleanup:** `/tmp/hermes-agent` clone removed.

**Status:** Acceptance criteria met. m16.2-m16.7 can now reference `discovery.md` for concrete env vars, domains,
state paths, and feature flags.

## 2026-05-25 - Proxy policy case-sensitivity gap surfaced before execution

While probing whether the proxy actually allows `git clone https://github.com/NousResearch/hermes-agent.git` after the
user added the entry to `user.policy.yaml`, the request kept returning 403 even after `agentbox proxy reload`.

**Issue:** Probes localized the cause:
- `https://github.com/mattolson/agent-sandbox.git/info/refs?service=git-upload-pack` → 200 (existing entry works)
- `https://github.com/NousResearch/hermes-agent.git/info/refs?service=git-upload-pack` → 403 (`Blocked by proxy
  policy: github.com`)
- `https://github.com/nousresearch/hermes-agent.git/info/refs?service=git-upload-pack` → 200 (lowercase works)

The proxy's repo matcher is case-sensitive on `owner/repo`, but GitHub serves the same repo regardless of case in the
URL. `git clone` uses the canonical upstream casing (`NousResearch`), so the mixed-case policy entry never matches the
actual request.

**Solution (workaround):** edit `.agent-sandbox/policy/user.policy.yaml` to use `nousresearch/hermes-agent`
(lowercase). The policy file is mounted read-only into the agent container, so the user applies the edit on the host.

**Decision:** Treat the lowercase entry as a workaround, not the durable fix. The matcher should case-fold
`owner/repo` because GitHub treats it as case-insensitive. Captured as a m14 follow-up in `learnings.md`; not blocking
m16.1.

**Learning:** Anyone adding a github `repos:` entry today must lowercase the owner. Until the matcher is fixed, mixed
case silently 403's.

**Follow-up finding:** After lowercasing the policy entry and reloading the proxy, the mixed-case request URL still
403'd. The matcher is case-sensitive on the **request path** as well, not just the policy entry. The full workaround
is twofold: (a) lowercase the `repos:` entry, AND (b) use a lowercase clone URL
(`https://github.com/nousresearch/hermes-agent.git`). GitHub serves both cases identically because the server is
case-insensitive. The durable matcher fix needs to case-fold on both sides.

## 2026-05-25 - Plan drafted

Initial task plan written. Two-track read strategy: prefer a local clone of
`github.com/NousResearch/hermes-agent` for exact greppable reads; fall back to
WebFetch against `raw.githubusercontent.com` if the clone is blocked.

**Decision:** WebFetch returns summarized content even when asked for verbatim
text (verified during milestone-definition planning: a "verbatim" request still
came back paraphrased). Local reads are the primary path. WebFetch is fallback
only, with narrowly scoped extraction prompts rather than verbatim asks.

**Decision:** Discovery output will be pinned to an upstream commit SHA at the
top of `discovery.md`, not "as of today", so the findings remain interpretable
when m16.2+ executes later.

**Observation:** Earlier exploration confirmed the upstream docs site
(`hermes-agent.nousresearch.com/docs`) is thin: it doesn't list env vars,
infrastructure domains, state paths, or sandbox flags. The README confirms
multi-provider support (Nous Portal, OpenRouter, NovitaAI, NVIDIA NIM, Xiaomi
MiMo, z.ai/GLM, Kimi/Moonshot, MiniMax, Hugging Face, OpenAI, custom endpoints)
— more providers than initially captured. Update milestone scope if any of
these need their own service entry beyond what users add themselves.

Awaiting approval to proceed to execution.
