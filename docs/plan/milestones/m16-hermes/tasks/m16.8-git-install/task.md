# Task: m16.8 - Hermes git editable install with minimal extras

## Summary

Replace the Hermes image's PyPI wheel install (`uv pip install hermes-agent==${HERMES_VERSION}` into
`/opt/hermes/.venv`, m16.2) with a pinned **git checkout + editable install** carrying a **curated extras set**
(`cli`, `mcp`, `acp` — deliberately **not** `web`). The git layout makes `detect_install_method()` return `"git"`,
which legitimately silences upstream's `⚠ pip install not officially supported` launch banner, and gives us explicit
control over which optional dependencies are baked in. The sandbox upgrade model (read-only install, no self-upgrade,
image-as-unit-of-upgrade) and network model are preserved unchanged.

## Background

The m16.2 image installs the PyPI wheel with no extras. Upstream's `hermes_cli/banner.py` prints a yellow
`⚠ pip install not officially supported — exists for reasons other than user install; expect instability and an
inability to support issues` line whenever `detect_install_method()` (`hermes_cli/config.py`) resolves to `"pip"`.
That resolution order is:

1. `~/.hermes/.install_method` stamp file
2. `HERMES_MANAGED` env / `.managed` marker
3. `.git` directory present → `"git"`
4. fallback → `"pip"`

Our wheel install writes no stamp and has no `.git`, so it falls through to `"pip"` and the banner fires. The warning
is accurate in the abstract, but most of its substance is already neutralized for us: self-update is disabled (the
`hermes` wrapper intercepts `update`/`uninstall`, venv is read-only), and "no support for pip installs" is moot for a
sandbox wrapper carrying its own workarounds. The one real gap is feature completeness — the wheel omits `ui-tui/`,
`web/`, and ships zero extras.

Two ways to clear the warning: stamp `.install_method` (cheap, keeps the wheel), or switch to a git checkout. We chose
git because it also lets us bake a curated extras set. See "Decision: git over stamp" below for the tradeoff.

## Decision: git over stamp, and the upgrade-surface caveat

- A git checkout silences the banner via `.git` presence (resolution step 3) — no stamp hack.
- It unlocks the `[all]`-eligible extras and the source-tree assets the wheel omits, while letting us install only the
  subset we want (`cli`, `mcp`, `acp`).
- **Cost / caveat (must be documented):** git widens the self-upgrade surface relative to the wheel.
  - Editable install (`uv sync` / `pip install -e`) means the running code *is* the source tree, so "modify yourself"
    is a file edit, not a reinstall.
  - The native upgrade path becomes `git pull` (keyed on **github.com**, a host our policies often allow) instead of
    `pip install --upgrade` (keyed on **pypi.org**, which we unconditionally block). This shifts the upgrade
    dependency onto a host we are more likely to permit.
  - The upstream installer's default layout puts the checkout under `$HERMES_HOME` (a persistent volume), which would
    make self-modification persist across restarts.
- These are mitigated, not eliminated, by: install root-owned + read-only at runtime, checkout placed **outside** the
  `hermes-state` volume, lazy installs disabled, and the `update`/`uninstall` wrapper retained. The read-only mount
  and egress policy remain the real controls; the wrapper is UX, not enforcement.

## Decision: hand-roll, do not run `install.sh`

`scripts/install.sh` is viable layout-wise — `HERMES_INSTALL_DIR` (code) and `HERMES_HOME` (data) are independent
env/flag overrides, so the volume-shadowing problem is avoidable. But the script **hardcodes `uv sync --extra all
--locked`** with no extras-selection flag, and pulls Node 22 / Playwright / ffmpeg. Since our whole point is a minimal
extras subset, we replicate the clone + `uv sync --extra ...` steps ourselves rather than fight the script.

## Decision: extras = `cli`, `mcp`, `acp`

From upstream `pyproject.toml` `[project.optional-dependencies]`:

- `cli` (`simple-term-menu`) — interactive terminal menus; tiny, pure-Python, used before the agent loop is alive.
- `mcp` (`mcp`, pinned `starlette`) — Model Context Protocol client for tool servers.
- `acp` (`agent-client-protocol`) — lets an external editor/IDE drive Hermes as an ACP agent.

Excluded: `web` (dashboard, FastAPI/uvicorn) for now; all lazy-only backends (`voice`, `matrix`, `messaging`,
`honcho`, `firecrawl`, `tts-premium`, `bedrock`, …); `homeassistant`, `sms`, `google`, `youtube` (niche / need their
own policy holes). `cron` and `pty` are empty no-op aliases — omitting them loses nothing. The bare wheel ships zero
extras and runs, so this set is additive, not load-bearing.

## Decision: versioning model (confirmed 2026-06-14)

Upstream maintains **two parallel version schemes for the same release**:

- **PyPI = semver** (`0.16.0`, latest as of confirmation).
- **Git tags = calver** (`v2026.6.5`).
- The GitHub **release name** embeds both: `"Hermes Agent v0.16.0 (2026.6.5) — The Surface Release"`.

PyPI carries **no programmatic link** to the git tag (`project_urls` is `null`; the sdist filename is just the
semver), so the calver tag we need to clone **cannot** be derived from PyPI. Therefore PyPI is dropped from the
pipeline entirely.

Design:

- **Source of truth = GitHub `releases/latest`.** It returns `tag_name` (the calver ref to clone) and the semver
  inside `name`. GitHub decides "latest" (newest non-prerelease), so we never sort tags ourselves — important because
  calver is **not** always three segments (e.g. `v2026.5.29.2`, a same-day re-release) and `releases/latest` also
  skips prereleases/drafts, which is the behavior we want.
- **Clone `tag_name`**: `HERMES_REF=v2026.6.5` → `git clone --branch "$HERMES_REF"`.
- **Image tag = calver** (`hermes-2026.6.5`) so the image tag, clone ref, and baked code are a single identifier with
  zero parsing in the GHCR "does this tag exist?" check.
- **Semver as an OCI label only** (`com.mattolson.agentsandbox.hermes-version=0.16.0`), parsed from the release
  `name` for human reference — never relied on mechanically (it is free-text).

## Scope

**Included:**
- Rewrite `images/agents/hermes/Dockerfile` to clone + editable-install at a pinned git ref with extras
  `cli,mcp,acp`.
- New layout: code at `/opt/hermes/hermes-agent` (keep `.git`), venv at `/opt/hermes/hermes-agent/venv`, data at
  `HERMES_HOME=/home/dev/.hermes` (unchanged, on the `hermes-state` volume).
- Build args: `HERMES_REF` (git tag/SHA, replaces `HERMES_VERSION`), `HERMES_EXTRAS` (default `cli,mcp,acp`),
  `EXTRA_PACKAGES` (apt, unchanged pattern).
- Update `images/agents/hermes/hermes-wrapper.sh` exec target to the new venv path; keep `update`/`uninstall`
  interception.
- Keep `images/agents/hermes/hermes-gateway-launch.sh` (PATH-resolved, no change).
- Keep the `sitecustomize.py` readline workaround (upstream #15768 still applies under editable install).
- Plant `~/.local/bin/hermes -> /opt/hermes/hermes-agent/venv/bin/hermes` for doctor's "Command Installation" check.
- **Drop** the `site-packages/.venv/bin/hermes` doctor symlink hack — the real `venv/` beside the source satisfies
  doctor's "Reinstall entry point" check natively.
- Lock down: `chown -R root:root /opt/hermes && chmod -R a+rX /opt/hermes` (dev runs non-root → read-only).
- `.github/workflows/check-hermes-version.yml`: switch source of truth from PyPI `.info.version` to GitHub
  `releases/latest` → `.tag_name` (calver); compare against the `hermes-<calver>` image in GHCR; trigger rebuild on
  drift.
- `.github/workflows/build-images.yml`: pass `HERMES_REF` (= the calver `tag_name`); tag image `hermes-<calver>`;
  optionally parse the semver from the release `name` into the OCI label.
- `images/build.sh`: thread `HERMES_REF` (and optional `HERMES_EXTRAS`) into the hermes build.
- `docs/agents/hermes.md`: rewrite install description, extras list, drop the obsolete doctor-symlink note, add the
  upgrade-surface security note.

**Excluded (no change):**
- Runtime network policy / `images/proxy/render-policy` / `images/proxy/addons/enforcer.py` — github is needed only
  at build time (CI has network); runtime egress is unaffected.
- CLI templates / devcontainer (`internal/embeddata/templates/hermes/`) — image-internal change only.
- `HERMES_YOLO_MODE=1`, `HERMES_DISABLE_LAZY_INSTALLS=1` env (unchanged).

**Explicitly out of scope (carried over from m16.2 v1 shape):**
- Node.js / npm / Ink TUI (`ui-tui/`), Playwright browsers, ffmpeg, the `web/` dashboard frontend.
- The `web` extra and all lazy-only backend extras.

## Acceptance Criteria

- [ ] `./images/build.sh hermes` (with a pinned `HERMES_REF`) builds on linux/amd64 **and** linux/arm64.
- [ ] `docker run --entrypoint "" <img> hermes --version` prints a non-empty version matching the pinned ref.
- [ ] Launch banner does **not** contain `pip install not officially supported`; `detect_install_method()` resolves
      to `git`.
- [ ] `hermes doctor` is clean — no "Reinstall entry point" and no "Command Installation" / missing-symlink warnings.
- [ ] Extras present: `import mcp`, `import simple_term_menu`, and the acp module import succeed in the venv; `import
      fastapi` **fails** (web excluded) without breaking the agent.
- [ ] `hermes update`/`hermes uninstall` fail against the read-only checkout (not intercepted; no wrapper). Upgrade
      procedure is documented instead.
- [ ] The `dev` user cannot write under `/opt/hermes` (no editable self-modify, no `git pull`).
- [ ] Lazy install still blocked: triggering an opt-in backend yields a clean unavailable error, no PyPI reach.
- [ ] Image carries `com.mattolson.agentsandbox.hermes-version=<ref>` label.
- [ ] `go test ./...` and the proxy Python suite pass (expected unaffected).
- [ ] Image size remains reasonable (compare against m16.2's 813 MB baseline; minimal extras should keep it close).

## Applicable Learnings

From m16.1/m16.2 and `docs/plan/learnings.md`:

- **`agent-sandbox-base` already provides** `git` (custom-compiled), `curl`, `ripgrep`, `build-essential`,
  `ca-certificates`, the `dev` user (UID 501). **Do not re-install** these. Base does **not** provide Python or `uv`
  — add `python3 python3-dev` and install `uv`.
- **Lazy installs are killed by `HERMES_DISABLE_LAZY_INSTALLS=1`** (env short-circuits `_allow_lazy_installs`); keep
  it.
- **One-shot `docker run` hangs** on base-derived images (firewall init needs `NET_ADMIN` + proxy). Use
  `--entrypoint ""` for probes; full runs via `agentbox exec`.
- **Layer ordering for cache:** apt + uv install (rarely changes) before the clone + `uv sync` (changes on every ref
  bump).

## Plan

### Files Involved

To modify:
- `images/agents/hermes/Dockerfile` (substantial rewrite)
- `images/agents/hermes/hermes-wrapper.sh` (exec path)
- `.github/workflows/check-hermes-version.yml` (PyPI → GitHub tags)
- `.github/workflows/build-images.yml` (build arg + tag)
- `images/build.sh` (build args)
- `docs/agents/hermes.md` (install/extras/upgrade/security)

To verify (may not need changes):
- `internal/runtime/agents.go` (image-tag/version scheme)

### Approach (Dockerfile, in read order)

1. `FROM ${BASE_IMAGE}`, `ARG BASE_IMAGE=agent-sandbox-base:local`.
2. **System deps as root, single layer:** `python3 python3-dev` plus the existing `EXTRA_PACKAGES` validation regex.
   (git/build-essential/curl/ripgrep/ca-certificates come from base.)
3. **Install pinned `uv`** to `/usr/local/bin/uv` (astral installer or pip — match repo convention; build-time only).
4. **`ARG HERMES_REF`** (git tag/SHA). **`ARG HERMES_EXTRAS=cli,mcp,acp`.**
5. **Clone:** `git clone --depth 1 --branch "$HERMES_REF" https://github.com/NousResearch/hermes-agent.git
   /opt/hermes/hermes-agent` (keep `.git`; add `git checkout <SHA>` if pinning by commit).
6. **Venv + editable install:** `uv venv /opt/hermes/hermes-agent/venv`, then with `UV_PROJECT_ENVIRONMENT` pointed
   there, `uv sync --extra cli --extra mcp --extra acp --locked` (hashed/reproducible from `uv.lock`).
7. **Readline workaround:** re-plant `sitecustomize.py` into the venv site-packages.
8. **Doctor symlink:** `~/.local/bin/hermes -> /opt/hermes/hermes-agent/venv/bin/hermes` (chown dev). Drop the old
   `site-packages/.venv` hack.
9. **Lock down:** `chown -R root:root /opt/hermes && chmod -R a+rX /opt/hermes`.
10. **`mkdir -p /home/dev/.hermes && chown dev:dev`** (unchanged).
11. **`COPY hermes-wrapper.sh /usr/local/bin/hermes`** + **`COPY hermes-gateway-launch.sh ...`**.
12. **`USER dev`**; ENV `HERMES_HOME`, `HERMES_YOLO_MODE=1`, `HERMES_DISABLE_LAZY_INSTALLS=1`;
    `CMD ["hermes-gateway-launch"]`; OCI labels with `${HERMES_REF}`.

### Implementation Steps

- [x] **Step 0 / discovery (version mapping):** confirmed semver/calver split; GitHub `releases/latest` chosen as the
      source of truth (Open Question 1 resolved). The arm64 `uv sync` confirmation (Open Question 2) still requires an
      actual build.
- [x] Rewrite Dockerfile per Approach.
- [x] Update `hermes-wrapper.sh` exec path.
- [x] Update the two workflows (`check-hermes-version.yml`, `build-images.yml`) and `images/build.sh`.
- [x] Update `docs/agents/hermes.md` (+ `CHANGELOG.md` Unreleased entry).
- [x] Verify `agents.go` (no change needed — it only lists `hermes` in `supportedAgents`); `go build ./...` and
      `go test ./...` pass; `bash -n images/build.sh` and workflow YAML validate.
- [x] Build locally and walk the acceptance criteria — verified on host (arm64): clean banner, green `hermes doctor`,
      `hermes update` intercepted (incl. with `~/.local/bin` on PATH), runs an existing install. Cross-arch amd64 left
      to the CI build matrix.

### Open Questions

1. **PyPI semver ↔ git calver tag mapping. — RESOLVED 2026-06-14.** Confirmed: PyPI is semver (`0.16.0`), git tags
   are calver (`v2026.6.5`), same release; PyPI exposes no link to the tag. Version tracking moves to GitHub
   `releases/latest`; clone `tag_name`; image tag = calver; semver as a label only. See the "Decision: versioning
   model" section above for the full rationale and caveats (4-segment calver, prerelease handling).
2. **Build-time compiler needs.** `cli`/`mcp`/`acp` + core are expected to resolve as prebuilt wheels (no compile),
   but core deps (pydantic-core, cryptography) need per-arch wheels; `build-essential` is already in base as a
   fallback. Confirm a clean `uv sync` on arm64.
3. **uv version to pin** and install method. — RESOLVED. Pinned to uv `0.11.21`, downloaded directly from the GitHub
   release and verified against per-arch SHA-256s (`UV_SHA256_AMD64`/`UV_SHA256_ARM64`) via `TARGETARCH`, mirroring the
   Codex image — not `curl | sh` (no checksum) or `pip install uv`.
4. **Does `--depth 1 --branch <tag>` leave a `.git` dir** sufficient for `detect_install_method` (it checks
   `(root/'.git').is_dir()`)? Expected yes; confirm during build.
5. **`agents.go` / image-tag scheme** — confirm whether the Go side encodes a version that needs updating for the
   `hermes-<git-tag>` naming.

## Outcome

_Complete; build-verified on host._ All static checks pass (`go build`/`go test`, `bash -n`, workflow YAML), and a host
build (Apple Silicon / arm64) confirmed: the launch banner no longer shows the pip warning, `hermes gateway status`
detects the running gateway, and the image runs an existing Hermes install. After the simplification below there is **no
wrapper**: `hermes` is the real, unmodified CLI symlinked onto PATH, so `hermes doctor` is fully green (`~/.local/bin/hermes`
points at the venv entry point) and `hermes update` simply fails against the read-only checkout (documented, not
intercepted). Cross-arch amd64 resolution of `uv sync` is left to the CI build matrix.

Files changed:
- `images/agents/hermes/Dockerfile` — git clone + editable `uv sync` with `HERMES_EXTRAS`; uv install; read-only
  lockdown; `hermes` symlinked onto PATH at `/usr/local/bin/hermes` and `~/.local/bin/hermes` (real, unmodified entry
  point); dropped the site-packages doctor symlink; `HERMES_REF`/`HERMES_SEMVER`/`HERMES_EXTRAS` build args.
- `images/agents/hermes/hermes-wrapper.sh` — **removed** (no longer wrap/intercept `update`/`uninstall`).
- `images/build.sh` — `HERMES_VERSION` (git tag or `latest`) resolution via GitHub release; `HERMES_EXTRAS`; new
  build args.
- `.github/workflows/check-hermes-version.yml` and `build-images.yml` — version source PyPI → GitHub `releases/latest`;
  image tag `hermes-<calver>`; semver as label.
- `docs/agents/hermes.md`, `CHANGELOG.md` — install layout, extras, upgrade path, self-upgrade-surface security note.

### Learnings (build verification)

- **Three-way constraint on the `hermes` entry point — you can keep all functional behaviors, but not a fully green
  `hermes doctor`.** The interactions, found one at a time on-image:
  1. *Update interception* needs the wrapper to win on PATH. The m16.2 "~/.local/bin is not on PATH" assumption is
     false — user dotfiles / the python stack / Debian's `~/.profile` prepend it ahead of `/usr/local/bin` — so a
     `~/.local/bin/hermes` symlink pointing at the real venv binary shadows the wrapper, and `hermes update` runs the
     real updater (which then fails with `fatal: detected dubious ownership in repository at '/opt/hermes/hermes-agent'`
     — the read-only lockdown blocking it as defense in depth, but with an ugly message).
  2. *Doctor's "Command Installation"* does a **strict equality** of `~/.local/bin/hermes` against the venv entry point
     path `.../.venv/bin/hermes` (confirmed by its `points to wrong target` warning when the symlink pointed at the
     wrapper). So satisfying doctor forces the symlink to the venv binary — which reintroduces (1).
  3. *Gateway status* (`hermes_cli/gateway.py::_scan_gateway_pids`) detects the gateway by scanning process command
     lines for patterns like `"hermes gateway"` / `"hermes_cli.main gateway"`. Making the wrapper the entry point by
     renaming the real script to `hermes-real` (the fix that satisfied 1+2) changed the gateway process cmdline to
     `.../hermes-real gateway run`, which matches **no** pattern → `gateway status` falsely reports "not running" even
     though the gateway is up. (The procps `ps eww -ax` Docker bug from issues #9723/#10761 is *not* the cause; this
     version scans `/proc` first.)
  Resolution (Approach R): leave the real console script as the untouched venv entry point, install the wrapper only at
  `/usr/local/bin/hermes` (execs the real binary), and do **not** plant `~/.local/bin/hermes`. This keeps update
  interception (1) and gateway detection (3) and the `hermes` program name, at the cost of one cosmetic doctor note
  (missing `~/.local/bin/hermes`). The lesson: don't rename or shadow the upstream entry point — too many of its
  behaviors (process self-detection, prog name) assume it is named `hermes` and is the real CLI.
- **Final decision: drop the wrapper entirely.** All of the above was machinery to turn one `hermes update` error into a
  clean message. Not worth it. The wrapper was removed: `hermes` is now the real, unmodified CLI symlinked onto PATH at
  both `/usr/local/bin/hermes` and `~/.local/bin/hermes`. With nothing to shadow or rename, constraint (1) collapses to
  "documented behavior" — `hermes update` fails on the read-only checkout (the read-only lockdown is the real enforcement
  anyway) — while (2) doctor is now **fully green** (the `~/.local/bin` symlink points at the venv entry point with no
  wrapper to conflict) and (3) gateway detection works. The proper upgrade procedure lives in `docs/agents/hermes.md`
  (Upgrading) and `CHANGELOG.md`.
