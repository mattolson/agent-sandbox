# Hermes Agent Sandbox Template

Run the [Hermes agent](https://hermes-agent.nousresearch.com/docs/) from Nous Research in a network-locked container. All outbound traffic is routed through an enforcing proxy that applies the project's network policy.

See the [main README](../../README.md) for installation, architecture overview, and configuration options.

## Setup

After running `agentbox init` (selecting "hermes") and starting the sandbox, configure your provider and authenticate Hermes.

### Provider configuration

Hermes is provider-agnostic. The default proxy policy only allows Hermes's own infrastructure (`hermes-agent.nousresearch.com` for the docs site, model catalog, and skills index). To call an LLM, add your chosen provider's service to your network policy.

For example, to use Hermes with Anthropic:

```yaml
# .agent-sandbox/policy/user.agent.hermes.policy.yaml
services:
  - claude
```

To use Hermes with OpenAI:

```yaml
services:
  - codex
```

To use Hermes with Nous Portal (the first-party hosted inference API), add the host directly:

```yaml
domains:
  - inference-api.nousresearch.com
```

Available provider services: `claude` (Anthropic), `codex` (OpenAI), `gemini` (Google), `copilot` (GitHub Copilot). For OpenRouter and other providers without a built-in service, add the host directly under `domains`.

Edit the policy with `agentbox edit policy`; active-policy changes hot-reload automatically when the proxy is running.

### First-run setup

The setup wizard makes network calls that require your provider's host to be reachable, so add the provider to your policy first (see [Provider configuration](#provider-configuration) above). Then inside the container:

```bash
hermes setup   # interactive setup wizard
hermes auth    # add a credential
```

Some wizard choices pull in optional features (skills hub, Honcho memory, Langfuse, Firecrawl) that need extra policy entries — see [Optional features](#optional-features) below. Both commands write to `HERMES_HOME`, so the configuration persists across `agentbox down && agentbox up`.

`hermes auth` is interactive: choose "Add a credential," then your provider. OAuth-capable providers run a device-code login (open the printed URL on the host, enter the code); API-key-only providers prompt for the key. If a provider's host isn't in the active policy, the device-code call will surface as a TLS error rather than a clean "blocked by policy" message — fix the policy first, then retry.

To change the active model later, run `hermes model`.

**Alternative: API keys via env vars.** For scripted or CI setups, flow keys through compose instead of `hermes auth`. Set them in `.agent-sandbox/compose/user.agent.hermes.override.yml`:

```yaml
# user.agent.hermes.override.yml
services:
  agent:
    environment:
      - NOUS_API_KEY=${NOUS_API_KEY}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

Export the matching key in your host shell before running `agentbox up`:

| Provider | Env var |
|----------|---------|
| Nous Portal | `NOUS_API_KEY` (with `NOUS_BASE_URL` for custom endpoints) |
| OpenRouter | `OPENROUTER_API_KEY` |
| OpenAI | `OPENAI_API_KEY` (with `OPENAI_BASE_URL` for OpenAI-compatible endpoints) |
| Anthropic | `ANTHROPIC_API_KEY` |
| Gemini | `GEMINI_API_KEY` |
| Novita | `NOVITA_API_KEY` |

Prefer `hermes auth` for interactive use.

### Use Hermes

Inside the container:

```bash
hermes chat
```

> **Auto-approval is on by default.** The sandbox image sets `HERMES_YOLO_MODE=1`, which disables the interactive confirmation prompts that normally gate shell-exec and other destructive or irreversible tool calls. Hermes self-approves these actions without asking. This is intentional for the sandbox context — the container is network-locked behind the enforcing proxy and the workspace is the only writable surface — but it means a misbehaving agent can run destructive commands against your mounted `/workspace` unattended. To restore prompting, override the env var to `0` in `.agent-sandbox/compose/user.agent.hermes.override.yml`.

Subcommands like `hermes model`, `hermes skills`, `hermes doctor`, and `hermes status` work as usual. Run `hermes --help` for the full list.

### Gateway

The image's default command starts `hermes gateway run` in the background when the container comes up, so the gateway is ready without any extra step. The container's lifetime is deliberately decoupled from it: the gateway runs under a `sleep infinity` keep-alive, so if the gateway exits the container stays up and `agentbox exec` keeps working. Gateway output appears in `agentbox logs agent`. To restart it, re-run `hermes gateway run` inside the container (it is not auto-restarted). To launch a different default process instead, set `command:` in `.agent-sandbox/compose/user.agent.hermes.override.yml`.

## Sandbox environment

The image sets these environment variables to keep Hermes well-behaved inside the locked-down container:

- `HERMES_HOME=/home/dev/.hermes` — state directory (learned skills, persona, sessions, credentials)
- `HERMES_YOLO_MODE=1` — auto-approve shell exec; sandbox already constrains the surface
- `HERMES_DISABLE_LAZY_INSTALLS=1` — Hermes can normally pip-install Python deps on demand from PyPI; the sandbox doesn't allow pypi.org, so this is disabled. Optional backends (Telegram, Honcho, etc.) will refuse to start instead of silently self-installing — bake them in at build time by adding their extra to `HERMES_EXTRAS` (see [Install layout](#install-layout)), or layer your own image

### Install layout

Hermes is installed from a **pinned git checkout**, not the PyPI wheel. The image shallow-clones the upstream release tag to `/opt/hermes/hermes-agent` and editable-installs it (`uv sync --locked`) into a sibling venv at `/opt/hermes/hermes-agent/.venv`. The whole tree is root-owned and read-only at runtime; the source lives outside the `HERMES_HOME` volume so the runtime mount never shadows it.

Two reasons for the git layout over the wheel:

- It silences upstream's `⚠ pip install not officially supported` launch banner legitimately — `detect_install_method()` keys on the `.git` directory and resolves to `git`.
- It lets us bake a **curated extras set** instead of the wheel's empty one. The build installs `cli` (interactive menus), `mcp` (Model Context Protocol client), and `acp` (Agent Client Protocol) — the `HERMES_EXTRAS` build arg (default `cli,mcp,acp`). The `web` dashboard and all lazy-only backends (voice, matrix, messaging, honcho, …) are deliberately excluded. To add one, rebuild with it appended to `HERMES_EXTRAS`; note some backends also need a build-time system dependency and a network-policy entry.

> **Security note.** A git editable install widens the self-upgrade surface relative to a wheel: the running code *is* the source tree (so "modify yourself" is a file edit), and the native upgrade path becomes `git pull` against github (a host policies often allow) rather than `pip install` against pypi (always blocked here). The mitigations are the read-only, root-owned `/opt/hermes` tree and the egress policy — **not** the wrapper, which is UX only. If your policy allows github at runtime, treat that as a security-relevant choice.

A small wrapper at `/usr/local/bin/hermes` intercepts `hermes update` and `hermes uninstall` (see [Upgrading](#upgrading)) and passes every other subcommand straight through to the real venv entry point, which is left untouched. Because nothing named `hermes` is planted in `~/.local/bin`, a PATH lookup resolves to the wrapper, so interception holds.

There's a deliberate trade-off here, governed by three constraints that can't all be satisfied at once:

- **Update interception** needs the wrapper to win on PATH.
- **`hermes doctor`**'s "Command Installation" check wants `~/.local/bin/hermes` to point (by strict equality) at the venv entry point `.venv/bin/hermes`.
- **`hermes gateway status`** detects the gateway by scanning process command lines for `.../hermes gateway`, so the entry point must keep the name `hermes`.

Planting `~/.local/bin/hermes → .venv/bin/hermes` (what doctor wants) would shadow the wrapper when `~/.local/bin` is ahead of `/usr/local/bin` on PATH — which it commonly is (user dotfiles, the python stack, Debian's `~/.profile`) — letting `update`/`uninstall` slip through to the read-only checkout and fail with a confusing git error. Making the wrapper *itself* the entry point (renaming the real binary) satisfies doctor but renames the gateway process and breaks status detection. So the image leaves the real entry point in place, installs the wrapper only on PATH, and does **not** plant `~/.local/bin/hermes`. Doctor's "Reinstall entry point" check still passes natively (the editable `.venv` sits beside the source), but its "Command Installation" check shows one cosmetic "missing `~/.local/bin/hermes`" note. That cosmetic line is the accepted cost of keeping update interception and gateway detection both working.

The image also plants `sitecustomize.py` in the venv's `site-packages` that does `import readline`. This works around upstream [hermes-agent#15768](https://github.com/NousResearch/hermes-agent/issues/15768): `hermes setup`'s free-text prompts (API keys, paths, y/n) call bare `input()` without importing `readline`, so arrow keys leak escape sequences as literal text instead of doing line editing. Python's `site` module auto-imports any module named `sitecustomize` at interpreter startup, which installs the readline hook before `input()` ever runs. Scoped to the hermes venv only — curses-based menus (`prompt_choice`, `prompt_checklist`) are unaffected.

## State persistence

`HERMES_HOME` is mounted on a named Docker volume (`hermes-state`), so learned skills, the persona Hermes builds of you, session history, and any provider credentials survive `agentbox down && agentbox up`. They do NOT survive `agentbox destroy` — that wipes all volumes by design.

Shell history persists on a separate `hermes-history` volume mounted at `/commandhistory`.

## Upgrading

`hermes update` and `hermes uninstall` are **intentionally disabled** in the sandbox. A wrapper at `/usr/local/bin/hermes` catches them and prints:

```
hermes update/uninstall is disabled in Agent Sandbox: the Hermes venv
is baked into the image and read-only at runtime. To upgrade, rebuild
the image:

    # on the host
    agentbox bump
    agentbox down && agentbox up
```

This is by design: the Hermes checkout and venv live under `/opt/hermes` and are read-only at runtime, and the sandbox model is "image is the unit of reproducible, reviewed state." In-place self-upgrades (`git pull` / editable edits) would defeat that. (Hermes also ships an upstream `HERMES_MANAGED` env var that would refuse `update` with a similar message, but it has side effects we don't want — it blocks `hermes setup` and requires the package manager to pre-create `~/.hermes/{cron,sessions,logs,memories}`. The wrapper gives us the same refusal without those side effects.)

The supported upgrade path:

1. The daily CI version-check workflow (`check-hermes-version.yml`) reads the latest `hermes-agent` GitHub release (the calver tag, e.g. `v2026.6.5`; the image is tagged `hermes-2026.6.5`).
2. When a new release appears, it triggers a rebuild of `agent-sandbox-hermes` and republishes it to GHCR.
3. Run `agentbox bump` to pull the new image digest.
4. `agentbox down && agentbox up` swaps to the new image. Your `HERMES_HOME` volume persists across the swap.

### Migrations

Some Hermes releases require explicit user-invoked migrations. These are **separate subcommands**, not triggered by upgrade:

- `hermes setup` — re-runs the interactive setup wizard. Useful after major config changes.
- `hermes gateway migrate-legacy` — migrates legacy gateway profiles.
- `hermes claw migrate` — migrates `claw` (skill collaboration board) state.

Watch upstream release notes for when these are needed.

### Snapshots

Before an upgrade (or any risky operation), snapshot `HERMES_HOME`:

```bash
hermes backup    # writes a zip under HERMES_HOME
```

Restore later with:

```bash
hermes import <backup.zip>
```

## Optional features

These features require additional network surfaces beyond the default `hermes` service. Add them to your policy only if you use the feature:

- **Skills hub** — `hermes skills publish`, `hermes skills fork`, etc. share skills via GitHub PRs. Requires `api.github.com`:
  ```yaml
  domains:
    - api.github.com
  ```
- **Honcho memory** — long-term agent memory provider. Requires `app.honcho.dev` and `HONCHO_API_KEY` set:
  ```yaml
  domains:
    - app.honcho.dev
  ```
- **Langfuse observability** — trace and prompt-cost observability. Requires `cloud.langfuse.com` and the `HERMES_LANGFUSE_*` env vars set:
  ```yaml
  domains:
    - cloud.langfuse.com
  ```
- **Firecrawl skill** — Nous-hosted web scraping. Requires `firecrawl-gateway.nousresearch.com`:
  ```yaml
  domains:
    - firecrawl-gateway.nousresearch.com
  ```

## Stop the container

For CLI mode:

```bash
agentbox compose down
```
