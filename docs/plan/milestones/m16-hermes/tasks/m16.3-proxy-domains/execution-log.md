# Execution Log: m16.3 - Hermes Proxy Service & KNOWN_AGENTS Entry

## 2026-05-27 - All acceptance checks pass

Made four edits as planned:

- `images/proxy/service_catalog.py`: added `"hermes": ["hermes-agent.nousresearch.com"]` between `gemini` and
  `opencode`.
- `images/proxy/render-policy`: added `"hermes"` to `KNOWN_AGENTS` (lexically between `gemini` and `opencode`).
- `images/proxy/tests/test_render_policy.py`: added `test_hermes_active_agent_expands_to_hermes_service_host` —
  renders an empty layered policy with `active_agent="hermes"` and asserts the service expansion produced
  `hermes-agent.nousresearch.com` with the default scheme rule.
- `images/agents/hermes/Dockerfile`: added `HERMES_MANAGED=AgentSandbox` to the ENV block.

**Tests:** all 172 proxy tests pass (`/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests`).
`go test ./...` still green.

**Sanity render in-sandbox** with `AGENTBOX_ACTIVE_AGENT=hermes` and empty user policy layers:

```
domains:
- host: hermes-agent.nousresearch.com
  rules:
  - schemes:
    - http
    - https
```

Exactly the expected shape.

**Image verification on host** (`verify-hermes-managed.sh`): rebuild is a no-op layer cache hit for the Python venv
and a thin new layer for the ENV addition. All 5 acceptance checks pass:

- Build succeeded
- HERMES_HOME, HERMES_YOLO_MODE, HERMES_DISABLE_LAZY_INSTALLS, HERMES_MANAGED all set correctly
- `hermes update --yes` exits with: "Cannot update Hermes Agent: this Hermes installation is managed by AgentSandbox.
  Use your package manager to upgrade or reinstall Hermes."
- Pip-install path was not reached (no `→ Running: ... pip install` line in output)

**Status:** task complete, ready for commit.

## 2026-05-27 - Plan expanded after researching `hermes update`

User pushed back on my dismissive "just don't allow pypi.org" position with: "there is a `hermes update` command that
manages upgrades — research it." They were right; I was waving it off too fast.

**Read `hermes_cli/main.py` and `hermes_cli/config.py` at the v2026.5.16 tag. Key findings:**

- `cmd_update` runs more than `pip install --upgrade`: pre-update backup (off by default, opt-in via `--backup` or
  `updates.pre_update_backup` config), git/zip/pip dispatch via `detect_install_method(PROJECT_ROOT)`, hangup
  protection wrapper, branch switching, stash management.
- For pip installs (our case), `_cmd_update_pip` runs `uv pip install --upgrade hermes-agent` or
  `python -m pip install --upgrade hermes-agent`. Would fail with EACCES against our root-owned
  `/opt/hermes/.venv` even if pypi.org were allowlisted.
- **`hermes update` does NOT trigger config/schema migrations.** Migrations are explicit user-invoked subcommands
  (`hermes gateway migrate-legacy`, `hermes claw migrate`, `hermes setup`). So the upgrade workflow doesn't need
  to do automatic state migration — that's a separate concern documented in m16.7.
- **Most importantly:** Hermes has first-class support for managed installs via `HERMES_MANAGED` env var.
  `get_managed_system()` reads it and `cmd_update` short-circuits with a managed-install error message.

**Decision:** set `HERMES_MANAGED=AgentSandbox` in the Dockerfile. With that:

- `hermes update` exits early with "Cannot update Hermes Agent: this Hermes installation is managed by AgentSandbox.
  Use your package manager to upgrade or reinstall Hermes." — clear, actionable, points users away from in-place
  self-upgrade and toward the `agentbox bump` workflow.
- We don't need to add pypi.org to any allowlist. The version-drift signal channel is m16.6's CI workflow.
- The Dockerfile change is technically a m16.2 follow-up but is one line; folded into m16.3 to keep the milestone
  diff atomic and avoid amending the just-committed m16.2.

**m16.7 scope expanded** in the milestone doc with explicit upgrade-path documentation requirements: explain why
`hermes update` is disabled, document the `agentbox bump` workflow, point at user-invoked migration subcommands and
the `hermes backup` / `hermes import` flow for pre-upgrade snapshotting.

**Original task scope (proxy service + KNOWN_AGENTS) unchanged**, just with the small Dockerfile ENV addition and a
couple more acceptance checks tacked on. Plan task.md updated.

## 2026-05-27 - Plan drafted

Smallest task in the milestone by a wide margin. Two-line code change plus one test.

**Architecture note from exploration:** the discovery doc (m16.1) referenced
`SERVICE_DOMAINS in images/proxy/addons/enforcer.py`, but that surface no longer exists post-m14. Services are now
declared in `images/proxy/service_catalog.py`'s `SIMPLE_SERVICE_HOSTS` dict, and `KNOWN_SERVICES` is derived
automatically from that. The discovery doc was written referencing an older mental model; not a bug in m16.1, just a
note for anyone reading both docs in sequence.

**One-domain rationale:** the `hermes` service entry stays minimal at `["hermes-agent.nousresearch.com"]`. That's the
docs site plus the model/skills JSON catalogs the CLI fetches at startup. All provider domains
(`*.anthropic.com`, `*.openai.com`, `openrouter.ai`, etc.) and opt-in Hermes-infra domains
(`inference-api.nousresearch.com` for Nous Portal, `firecrawl-gateway.nousresearch.com` for the firecrawl skill,
`api.github.com` for skills-hub PRs) stay user-managed per the provider-agnostic agent pattern Pi and OpenCode set.

Awaiting approval to proceed to execution.
