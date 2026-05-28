# Execution Log: m16.2 - Hermes Dockerfile

## 2026-05-27 - Acceptance verification complete

`verify-hermes-image.sh` ran clean on host (Apple Silicon / Colima). All 8 checks pass:

- Build: 19.4 s on first run, 0.2 s cached on the re-run.
- `hermes --version`: `Hermes Agent v0.14.0 (2026.5.16)` — semver + calver shown together, project path
  `/opt/hermes/.venv/lib/python3.11/site-packages`, OpenAI SDK 2.24.0, "Up to date" (PyPI check reachable from host).
- ENV: `HERMES_HOME=/home/dev/.hermes`, `HERMES_YOLO_MODE=1`, `HERMES_DISABLE_LAZY_INSTALLS=1` all correct.
- `/home/dev/.hermes`: `dev:dev 755` ownership.
- OCI labels: description and `com.mattolson.agentsandbox.hermes-version=0.14.0` both present.
- Image size: **813 MB**. Reasonable; well under the 1 GB target. Base is the bulk; Hermes layer adds ~230 MB.
- `hermes` resolves on PATH at `/usr/local/bin/hermes`; `hermes --help` runs cleanly as the dev user.

**Issue encountered, fixed:** initial verify script ran `docker run --rm $IMG hermes --version` (no entrypoint
override), which hangs because `agent-sandbox-base`'s entrypoint runs `init-firewall.sh` and that requires
`NET_ADMIN` + a proxy sidecar. Build-time `RUN hermes --version` inside the Dockerfile already validated the install;
for runtime probes we now pass `--entrypoint ""` to skip the firewall entrypoint. Logged as a general agent-image
learning in `docs/plan/learnings.md`.

**Multi-arch:** local build on Colima/Apple Silicon is native arm64 (per CLAUDE.md "Primary target: Colima on Apple
Silicon"). Cross-arch validation belongs to m16.6's CI matrix where buildx builds both amd64 and arm64. Not blocking
m16.2.

**Spike artifacts (`spike-hermes-pypi.sh`, `verify-hermes-image.sh`) live at the repo root, not committed.** They
served their purpose; user can `rm` them whenever.

**Status:** acceptance criteria met. m16.2 complete pending commit.

## 2026-05-27 - Spike complete, Dockerfile written

Ran the PyPI spike (`spike-hermes-pypi.sh`) on host inside `python:3.11-slim`. Results:

- **PyPI install works fast and clean.** 3.2 seconds, no `build-essential`/`gcc`/`libffi-dev` triggered. Confirms
  modern Python wheels handle multi-arch (Colima emulated aarch64 in the spike, which is the Apple Silicon target).
- **Plain CLI is functional without `ui-tui/`.** `hermes --help` listed the full subcommand surface (chat, model,
  gateway, doctor, etc.) cleanly. No ImportError, no Node-related failure. **v1 shape is locked.**
- **`get_hermes_home()` returns `~/.hermes` by default.** No env var needed for that; just `mkdir` + chown.
- **PyPI version is `0.14.0`, not `2026.5.16`.** Upstream maintains two version tracks: semver on PyPI, calver on
  git tags. `hermes --version` prints both: `Hermes Agent v0.14.0 (2026.5.16)`. `HERMES_VERSION` in the Dockerfile
  uses the PyPI semver form (which is also what `pypi.org/.../json` returns for the CI version check). Added a
  Dockerfile comment to flag this.
- **Skills are NOT in the PyPI wheel.** `find /usr/local /opt -name skills` found only the openai SDK's internal
  skill dirs, not Hermes's `skills/` or `optional-skills/`. `setup.py:data_files` either silently dropped them or
  shipped them somewhere unfindable. **Not a blocker:** `hermes --help` works without them, suggesting Hermes
  either fetches skills lazily from `hermes-agent.nousresearch.com/docs/api/skills-index.json` (already allowlisted)
  or has no required-at-startup bundled skills. Will verify in real chat use; if broken, set
  `HERMES_BUNDLED_SKILLS` to wherever data_files ended up, or fall back to clone-install.

**Two strategy refinements that came out of digging into the source:**

- **Drop `uv` entirely.** Originally added for lockfile fidelity, but we pin to a PyPI version that resolves the
  same deps via pip. `python3 -m venv` + the venv's bundled pip is enough. Cuts out the curl-pipe-sh question
  (rejected) and the `pip install uv` + PEP 668 `--break-system-packages` workaround. Simpler image.
- **Don't bake `cli-config.yaml` for lazy installs.** Reading `tools/lazy_deps.py:_allow_lazy_installs` confirmed
  the env var `HERMES_DISABLE_LAZY_INSTALLS=1` is checked **before** the config file and short-circuits the loader.
  Setting it in `ENV` achieves the same goal as baking a YAML, with one less file to maintain. Original plan said
  "bake `cli-config.yaml`"; corrected to "set env var instead."

**Dockerfile written at `images/agents/hermes/Dockerfile`.** Shape:

- `FROM ${BASE_IMAGE}` (agent-sandbox-base provides git, curl, ripgrep, procps, dev user, firewall)
- apt-get `python3 python3-venv` (drops `python3-pip` since venv brings its own; drops `build-essential gcc
  libffi-dev` since the spike showed no native compilation is needed)
- `python3 -m venv /opt/hermes/.venv && /opt/hermes/.venv/bin/pip install hermes-agent==0.14.0`
- Symlink `/opt/hermes/.venv/bin/hermes` to `/usr/local/bin/hermes`
- `chmod -R a+rX /opt/hermes` (read-only from dev user's perspective; build immutable)
- `mkdir /home/dev/.hermes`, chown to dev
- ENV: `HERMES_HOME`, `HERMES_YOLO_MODE=1`, `HERMES_DISABLE_LAZY_INSTALLS=1`
- OCI labels

No `cli-config.yaml` file in the image; the env var pattern handles the v1 needs.

**Open implementation questions resolved:**

1. ~~Plain CLI without ui-tui~~ — works. Confirmed.
2. ~~Skills resolution under non-editable install~~ — skills not in wheel, but CLI runs fine. Deferred; will surface
   if real interaction needs them.
3. ~~YAML nesting for `security.allow_lazy_installs`~~ — moot; using env var instead.
4. ~~System config path~~ — moot; no config file in v1.
5. ~~Image size~~ — to be measured after build. Should be small without uv/clone/extras.

**Next step:** user builds locally and verifies acceptance criteria. Build command:

```
./images/build.sh base   # if agent-sandbox-base:local doesn't exist
docker build -t agent-sandbox-hermes:local \
  --build-arg BASE_IMAGE=agent-sandbox-base:local \
  -f images/agents/hermes/Dockerfile \
  images/agents/hermes/
```

Then verify:

```
docker run --rm agent-sandbox-hermes:local hermes --version
docker run --rm agent-sandbox-hermes:local printenv HERMES_HOME HERMES_YOLO_MODE HERMES_DISABLE_LAZY_INSTALLS
docker inspect agent-sandbox-hermes:local --format '{{ index .Config.Labels "com.mattolson.agentsandbox.hermes-version" }}'
docker images agent-sandbox-hermes:local --format '{{ .Size }}'  # size check
```

## 2026-05-27 - Strategy correction: PyPI install, not clone-install

User pushed back: "since we're only installing tagged versions of hermes, why should we use git at all? why not just
install from pip?"

Reviewed my own justifications for clone-install and most were weak:

- "PyPI wheel omits `ui-tui/` and `web/`" — true, but v1 explicitly skips both.
- "Editable install matches upstream's `setup-hermes.sh`" — appeal to authority; upstream are developers iterating on
  the source, we just want the published artifact.
- "`skills/` are `data_files` in setup.py" — they ARE in the wheel; PyPI install gets them, just at a different
  on-disk location (`<sys.prefix>/skills/`) than editable (`/opt/hermes/skills/`).

The only real concern is whether Hermes's runtime path resolution finds skills at the `data_files` location under a
non-editable install. The presence of the `HERMES_BUNDLED_SKILLS` env var (from m16.1 enumeration) strongly suggests
this is configurable, but needs runtime verification.

**Decision:** switch v1 install strategy from clone-install to `uv pip install hermes-agent==${HERMES_VERSION}` from
PyPI. Significantly simpler Dockerfile. Drops:

- `git clone` (no longer needed)
- `build-essential gcc libffi-dev` from the default deps (modern Python wheels handle compilation; add back if a
  transitive needs to build from source)
- `/opt/hermes` as a 30 MB clone tree (now just the venv)

**Version anchor changes form:** `HERMES_VERSION=2026.5.16` (PyPI normalizes the `v` prefix off), not the git-tag form
`v2026.5.16`. CI version check (m16.6) already queries PyPI, so the value used in the Dockerfile and the value
checked in CI are the same string. Add a Dockerfile comment to flag the no-`v` convention.

**Spike now verifies two things, not one:**

1. Plain CLI starts without the Node `ui-tui/` (the original m16.1 gating question).
2. `hermes` can find its bundled skills under PyPI install (the new gating question).

**Fallback ordering if PyPI install proves broken:**

- First: set `HERMES_BUNDLED_SKILLS` to wherever `data_files` placed the skills (probably `<venv>/skills`).
- Second: revert to clone-install (the prior plan, preserved in this log).

**Learning logged:** when designing an image install path, default to the published distribution (PyPI / npm /
GitHub release) before considering source clone. Source clone is justified by editability needs or by missing
artifacts in the published distribution; "matches upstream" is not a sufficient reason on its own.

**task.md updated:** Summary, Scope, Acceptance Criteria, Approach, Implementation Steps, and Open Questions all
revised. Clone-install path is now the documented fallback, not the primary.

## 2026-05-25 - Plan drafted

Initial task plan written. Strategy is the one settled in m16.1: clone at pinned tag, `uv pip install -e .`, skip
Node/Playwright/ffmpeg/s6 for v1.

**Key planning decisions:**

- **Use Astral's `uv` installer (curl-pipe-sh) at build time.** This is the same kind of pattern we rejected for
  upstream's `scripts/install.sh`, but the surface is different: uv's installer is a tiny, signed, single-purpose
  binary download (not 82 KB of OS detection, desktop integration, and interactive prompts). Alternatives considered:
  `pip install uv` (requires pip and a chosen Python first; works but adds a step), and `COPY --from=ghcr.io/astral-sh/uv`
  multi-stage (cleanest, but introduces an external image dep). uv installer wins on simplicity at build time.
- **Editable install, not `uv sync --frozen`.** `uv pip install -e .` from the clone is what upstream's
  `setup-hermes.sh` does and keeps `skills/`/`optional-skills/` resolvable from the source tree (which `setup.py:data_files`
  expects). `uv sync --frozen` honors `uv.lock` exactly but doesn't play as cleanly with editable + data_files.
  Re-evaluate if v1 install drift causes problems.
- **No extras for v1.** Core `dependencies = [...]` in pyproject.toml covers OpenAI / OpenAI-compatible providers
  (including OpenRouter and Nous Portal). Native Anthropic / Gemini / firecrawl / messaging adapters live in extras
  and are deferred to a follow-up. Adding `[cli]` (simple-term-menu) is the most likely v1 expansion if the spike
  surfaces an ImportError; record the decision when made.
- **Spike comes first in execution.** Before writing the production Dockerfile, verify that hermes runs without
  `ui-tui/`. This is the v1-shape gating question from m16.1. If the spike fails, the task expands to include Node +
  workspace build.
- **`com.mattolson.agentsandbox.hermes-version` label, not `org.opencontainers.image.version`.** Match Codex's
  custom-namespaced label pattern; OCI version label is set by the value at the top-level metadata layer.

**Open implementation questions deferred to execution:**

1. Exact YAML path for `security.allow_lazy_installs` in `cli-config.yaml`.
2. Whether Hermes reads a system config at `/etc/hermes/cli-config.yaml`, or only `$HERMES_HOME/cli-config.yaml`.
3. Whether the plain CLI starts without the Ink TUI.

These can't be answered cleanly from static inspection of upstream; they need a runtime probe.

Awaiting approval to proceed to execution.
