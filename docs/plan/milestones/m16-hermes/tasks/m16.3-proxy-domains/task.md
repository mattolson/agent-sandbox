# Task: m16.3 - Hermes Proxy Service, KNOWN_AGENTS, and Managed-Install Marker

## Summary

Register Hermes in the proxy's semantic service catalog and in the list of agent names the renderer will accept as
`AGENTBOX_ACTIVE_AGENT`. After this, setting `AGENTBOX_ACTIVE_AGENT=hermes` and reloading the proxy produces a
rendered policy that includes the Hermes infrastructure host (`hermes-agent.nousresearch.com`) automatically. Also
set `HERMES_MANAGED=AgentSandbox` in the agent image so `hermes update` refuses with a clear error pointing users to
the `agentbox bump` upgrade path — folded in here as a small m16.2 follow-up to keep the milestone diff atomic.

## Scope

**Included:**
- One entry in `SIMPLE_SERVICE_HOSTS` in `images/proxy/service_catalog.py`:
  `"hermes": ["hermes-agent.nousresearch.com"]`.
- One addition to `KNOWN_AGENTS` in `images/proxy/render-policy`: append `"hermes"`.
- One line added to the `ENV` block in `images/agents/hermes/Dockerfile`: `HERMES_MANAGED=AgentSandbox`. Upstream
  Hermes reads this env var (see `hermes_cli/config.py:get_managed_system`) and `cmd_update` checks `is_managed()`
  before running. With this set, `hermes update` exits early with: "Cannot update Hermes Agent: this Hermes
  installation is managed by AgentSandbox. Use your package manager to upgrade or reinstall Hermes." Right behavior,
  good error message.
- Test coverage that asserts `AGENTBOX_ACTIVE_AGENT=hermes` produces a rendered policy whose domains include
  `hermes-agent.nousresearch.com`. Mirror the closest existing pattern (probably a parameterized test or a small
  new test method in `test_render_policy.py`).
- Verify the new env var is set in the rebuilt image (extend `verify-hermes-image.sh` locally, or add to the existing
  ENV check).
- Full proxy test-suite green after the changes.

**Explicitly out of scope:**
- Provider-side domains. Per discovery, Hermes is provider-agnostic (Nous Portal / OpenRouter / OpenAI / Anthropic /
  Gemini / Novita / OLLAMA / custom). The `hermes` service stays minimal; users add the provider service they actually
  use (`claude`, `codex`, `openai`-via-`codex`, `gemini`, etc.) to their own policy.
- Opt-in Hermes-infra domains: `inference-api.nousresearch.com` (only if Nous Portal is the active provider),
  `firecrawl-gateway.nousresearch.com` (only if firecrawl skill is used), `api.github.com` (only for skills-hub
  PRs). These remain user-managed and are documented in m16.7's `docs/agents/hermes.md`.
- pypi.org. The `HERMES_MANAGED` marker means `hermes update` short-circuits before any pip call, so there's no
  reason to allowlist pypi.org. The version-drift signaling channel is m16.6's CI workflow.
- Upgrade documentation itself. m16.7's `docs/agents/hermes.md` will document the upgrade path (CI version-check
  PR → `agentbox bump`) and the deliberate disable of `hermes update`. This task just sets the env var that triggers
  the right error message.
- The Go CLI agent registry (`internal/runtime/agents.go`). That's m16.5.
- Templates, build wiring, agent docs — m16.4, m16.6, m16.7 respectively.

## Acceptance Criteria

- [ ] `images/proxy/service_catalog.py` has a `"hermes"` entry in `SIMPLE_SERVICE_HOSTS` containing exactly
      `["hermes-agent.nousresearch.com"]`.
- [ ] `images/proxy/render-policy`'s `KNOWN_AGENTS` set includes `"hermes"` (lexically sorted to match the existing
      ordering convention).
- [ ] `images/agents/hermes/Dockerfile` ENV block sets `HERMES_MANAGED=AgentSandbox`.
- [ ] Rebuilt image: `docker run --entrypoint "" agent-sandbox-hermes:local printenv HERMES_MANAGED` prints
      `AgentSandbox`.
- [ ] Rebuilt image: `docker run --entrypoint "" agent-sandbox-hermes:local hermes update --yes` exits non-zero
      (or prints the managed-install error and returns) without invoking pip. Acceptable forms include the literal
      string `managed by AgentSandbox` in the output.
- [ ] A test in `images/proxy/tests/` asserts that `render_layered_policy("hermes")` produces a domains list that
      contains `hermes-agent.nousresearch.com`.
- [ ] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'` passes.
- [ ] `go test ./...` still passes (no Go changes expected, but sanity check).

## Applicable Learnings

- **Proxy catalog architecture (m14):** new agent services land in `SIMPLE_SERVICE_HOSTS` in `service_catalog.py`,
  not in `SERVICE_DOMAINS` in `enforcer.py` — that older surface was removed by m14. `KNOWN_SERVICES` is derived
  automatically from `SIMPLE_SERVICE_HOSTS.keys() | RICH_SERVICES`, so no separate registration is needed for
  validation.
- **Proxy test interpreter:** use `/opt/proxy-python/bin/python3`, not system Python — only the dev-image venv has
  `mitmproxy`, `pytest`, and `PyYAML`.
- **Provider-agnostic agent convention (Pi/OpenCode precedent):** the agent's service entry covers only its own
  infrastructure; provider domains stay user-managed and are documented in the agent doc. Pi has `[]` as its service
  list because Pi has no infra of its own; OpenCode has `["opencode.ai", "*.opencode.ai", "models.dev"]`. Hermes sits
  between them — one infrastructure domain — and follows the same pattern.

## Plan

### Files Involved

To modify:
- `images/proxy/service_catalog.py` — add `"hermes"` entry to `SIMPLE_SERVICE_HOSTS`.
- `images/proxy/render-policy` — add `"hermes"` to `KNOWN_AGENTS`.
- `images/agents/hermes/Dockerfile` — add `HERMES_MANAGED=AgentSandbox` to the ENV block.

To modify (test):
- `images/proxy/tests/test_render_policy.py` — add a test method asserting the hermes service expansion. Use the
  existing `render_layered` helper at line 93. Match the shape of whatever pattern already covers the simpler agents
  (claude, codex, opencode).

### Approach

1. **Inspect existing test pattern.** Read `test_render_policy.py` around the `render_layered` helper to see how
   existing agent expansions are tested (or if they are at all). If no per-agent test exists, add the simplest
   possible one for hermes; don't retroactively cover the others.
2. **Edit `service_catalog.py`.** Add the entry alphabetically between `gemini` and `opencode` (or wherever the
   existing alphabetical convention places it; on inspection the existing list is NOT strictly alphabetical —
   `pi` and `copilot` come after `opencode` — so insertion order is loose. Pick a spot that fits visually.)
3. **Edit `render-policy`.** Add `"hermes"` to the `KNOWN_AGENTS` set. The set is currently sorted alphabetically:
   `{"claude", "codex", "copilot", "factory", "gemini", "opencode", "pi"}`. New ordering:
   `{"claude", "codex", "copilot", "factory", "gemini", "hermes", "opencode", "pi"}`.
4. **Add the test.** Smallest viable case: render a layered policy with `active_agent="hermes"` and assert
   `hermes-agent.nousresearch.com` appears among the rendered hosts.
5. **Run the full proxy test suite.** Confirm green.
6. **Sanity render** outside tests: invoke `render-policy` with `AGENTBOX_ACTIVE_AGENT=hermes` and look at the
   rendered YAML. Useful for the execution log.

### Implementation Steps

- [ ] Read `images/proxy/tests/test_render_policy.py` around `render_layered` to pick the test pattern to mirror.
- [ ] Add hermes entry to `SIMPLE_SERVICE_HOSTS`.
- [ ] Add `"hermes"` to `KNOWN_AGENTS`.
- [ ] Add the test method.
- [ ] Add `HERMES_MANAGED=AgentSandbox` to the Dockerfile's ENV block.
- [ ] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`.
- [ ] Run `go test ./...` for the no-regression check.
- [ ] Render a layered policy with `AGENTBOX_ACTIVE_AGENT=hermes` via the CLI as a sanity check, capture output in
      the execution log.
- [ ] Rebuild the image on host and verify `printenv HERMES_MANAGED` returns `AgentSandbox` and `hermes update --yes`
      refuses with the managed-install error message.

### Open Questions

None substantive. The pattern is established (m11-pi, m12-opencode added the same kind of entries), the m14
architecture is well-understood, and the discovery doc named exactly the single domain to include.

One minor judgment call surfaces only if it comes up:

- If the existing `test_render_policy.py` doesn't have any per-agent expansion test today (only mechanical merge
  tests), do we still add one for hermes? **Yes** — even one is better than none, and downstream tasks
  (m16.6 build/CI) will lean on it as a regression canary. Don't backfill the other agents in this task; that's
  unrelated scope.

## Outcome

Completed 2026-05-27. Four small code edits + one test, all proxy and Go tests pass, host-side rebuild verifies the
managed-install marker takes effect.

### Acceptance Verification

- [x] `service_catalog.py` has `"hermes": ["hermes-agent.nousresearch.com"]` in `SIMPLE_SERVICE_HOSTS`
- [x] `render-policy` `KNOWN_AGENTS` includes `"hermes"`
- [x] `Dockerfile` ENV includes `HERMES_MANAGED=AgentSandbox`
- [x] Rebuilt image: `printenv HERMES_MANAGED` returns `AgentSandbox`
- [x] Rebuilt image: `hermes update --yes` prints "managed by AgentSandbox" and does not reach the pip-install path
- [x] New test `test_hermes_active_agent_expands_to_hermes_service_host` asserts the service expansion
- [x] All 172 proxy tests pass
- [x] `go test ./...` still passes

### Learnings

Nothing new to append to `docs/plan/learnings.md` from this task — the architecture (`SIMPLE_SERVICE_HOSTS` +
`KNOWN_AGENTS`), the test pattern (`render_layered("agent")`), and the case-sensitivity workaround (from m16.1) were
all already captured. The `HERMES_MANAGED` finding is a Hermes-specific implementation detail rather than a general
sandbox lesson.

### Follow-up Items

- **m16.7** picks up the upgrade-path documentation (now in milestone scope): `docs/agents/hermes.md` must explain
  why `hermes update` is disabled, what to do instead (`agentbox bump` flow), and that user-invoked migration
  subcommands (`hermes gateway migrate-legacy`, `hermes claw migrate`, `hermes setup`) plus `hermes backup` /
  `hermes import` remain available.
