---
name: add-agent
description: Add a new AI coding agent to Agent Sandbox. Creates all required files (Dockerfile, templates, CI, docs) and wires the agent into the CLI, proxy, and build system.
---

# Scaffold Agent Support

This skill generates all the files needed to add a new AI coding agent to Agent Sandbox. It follows the established patterns from Claude, Copilot, and Codex implementations.

## Arguments

The skill takes a single argument: the agent name (lowercase, no spaces). Example: `gemini`, `opencode`, `factory`.

## Process

### Step 1: Gather Information

Ask the user for the following (skip any already provided):

1. **Agent name** (from argument)
2. **Display name** - human-readable name for comments and labels (e.g., "Google Gemini CLI")
3. **Project URL** - link to the agent's GitHub repo or website (for README table)
4. **Installation method** - how to install the agent binary/CLI
   - npm package (like Claude and Copilot)
   - direct binary download from GitHub releases (like Codex)
   - curl installer script
   - pip package
   - go install
5. **Package identifier** - npm package name, GitHub releases URL pattern, pip package, go module, or download URL
6. **Version detection source** - how CI detects new releases
   - npm registry (Claude, Copilot): `npm view {package} version`
   - GitHub releases API (Codex): `gh api repos/{owner}/{repo}/releases/latest --jq .tag_name`
   - Note any tag prefix that needs stripping (e.g., Codex uses `rust-v` prefix)
7. **Version variable name** - env var for build.sh (e.g., `GEMINI_VERSION`)
8. **Config directory** - where the agent stores its config in the container (e.g., `/home/dev/.gemini`)
9. **Default config files** - any config files to bake into the image (e.g., Codex bakes `config.toml` to disable its internal sandbox)
10. **Internal sandbox** - does the agent have its own sandboxing (Landlock, seccomp, etc.) that should be disabled inside our container? If so, how to disable it.
11. **Required API domains** - domains the agent needs to reach (API, auth/OAuth, CDN)
12. **Authentication method** - how users authenticate (API key env var, OAuth flow, device code, etc.)
13. **Auto-approve flag** - the CLI flag for unattended/yolo mode (e.g., `--dangerously-skip-permissions`, `--yolo`, `--full-auto`)
14. **VS Code extension ID** - if one exists (e.g., `github.copilot-chat`), or "none" for CLI-only agents
15. **JetBrains plugin ID** - if one exists (e.g., `com.anthropic.code.plugin`), or "none"
16. **Agent-specific environment variables** - any env vars the agent needs at runtime
17. **Does the agent need Node.js?** - whether to install Node.js in the Dockerfile (only if the base image doesn't include it and the agent needs it)

### Step 2: Create Files

Generate all files listed below. Read the reference files first to match the exact format and structure.

#### 2.1: Dockerfile

Create `images/agents/{agent}/Dockerfile`.

Pattern:
- `ARG BASE_IMAGE=agent-sandbox-base:local` + `FROM ${BASE_IMAGE}`
- Optional extra packages block (same pattern as existing agents)
- Install Node.js if needed (copy pattern from Copilot Dockerfile)
- As root: create config directory and `~/.local/bin` if installing a binary there
- Copy any default config files (e.g., `COPY config.toml /home/dev/.{agent}/config.toml`)
- `USER dev`
- Set `ENV PATH="/home/dev/.local/bin:$PATH"` if installing to `~/.local/bin`
- Install the agent (method depends on installation type)
- For direct binary downloads: use `ARG TARGETARCH` for multi-arch, prefer musl (statically linked) over gnu variants
- Add labels: `org.opencontainers.image.description` and version label

If the agent needs default config files, create them alongside the Dockerfile (e.g., `images/agents/{agent}/config.toml`).

#### 2.2: Agent Compose Layer

Create `cli/templates/{agent}/cli/agent.yml`.

This is a compose overlay that layers on top of the shared `cli/templates/compose/base.yml`. It contains only agent-specific configuration. Read an existing agent.yml for the exact format.

Contents:
- Managed-by comment header
- `services.proxy.volumes: []` (required placeholder for compose merge)
- `services.agent.image` - the GHCR image reference
- `services.agent.volumes` - agent-specific state and history volumes
- `services.agent.environment` - agent-specific env vars (if any)
- Named volume declarations at the bottom

Do NOT include proxy config, HTTP_PROXY, HTTPS_PROXY, capabilities, or other shared settings. Those live in `base.yml`.

#### 2.3: devcontainer.json

Create `cli/templates/{agent}/devcontainer/devcontainer.json`.

This file references a layered array of compose files. Read an existing devcontainer.json for the exact format.

Key points:
- `dockerComposeFile` is an array of 5 paths pointing into `.agent-sandbox/compose/`:
  `base.yml`, `agent.{name}.yml`, `mode.devcontainer.yml`, `user.override.yml`, `user.agent.{name}.override.yml`
- `service: "agent"`
- `workspaceFolder: "/workspace"`
- VS Code settings section with port forwarding disabled and security settings
- VS Code extensions array if applicable, or omit for CLI-only agents
- JetBrains settings section with proxy configuration
- JetBrains plugins array if applicable
- `remoteUser: "dev"`
- `overrideCommand: false`

#### 2.4: Update Agent Registry

Edit `cli/lib/agent.bash`:
- Add the new agent to `supported_agents_display()` (space-separated string)
- Add the new agent to `supported_agents()` (printf list)
- Add the new agent to `select_agent()` (option list)
- Add the new agent to the `validate_agent()` case statement

#### 2.5: Update CLI Compose Scaffolding

Edit `cli/lib/cli-compose.bash`:
- If the agent has host-side config that users might want to mount (like Claude's `CLAUDE.md` and `settings.json`), add a conditional block in `scaffold_cli_agent_override_if_missing()` following the Claude pattern. This adds commented-out volume entries to `user.agent.{name}.override.yml`.
- Skip this for agents without meaningful host-side config.

#### 2.6: Update BATS Tests

Two test files reference the agent list string:

1. Edit `cli/test/init/init.bats`: update the "rejects invalid --agent value" assertion to include the new agent name.
2. Edit `cli/test/switch/switch.bats`:
   - Update the "switch rejects invalid --agent value" assertion(s) to include the new agent name.
   - Update the `stub select_option` call in "switch prompts for agent when --agent is omitted" to include the new agent in the argument list.

Both assertions and the stub match the output of `supported_agents_display()` / `select_agent()`.

#### 2.7: Update Proxy Service Domains and Known Agents

Two files in the proxy image need updating:

**`images/proxy/addons/enforcer.py`**: add a new entry to `SERVICE_DOMAINS` dict.

Guidelines:
- Place alphabetically among existing entries
- Prefer wildcards over listing subdomains individually (e.g., `*.openai.com` covers `api.openai.com`, `auth.openai.com`, regional endpoints)
- Only use separate entries for different TLDs (e.g., `chatgpt.com` is separate from `openai.com`)
- Include both API domains and auth/OAuth domains so authentication works through the proxy

**`images/proxy/render-policy`**: add the new agent name to the `KNOWN_AGENTS` set. This script renders the effective proxy policy at startup and validates the `AGENTBOX_ACTIVE_AGENT` env var against this set. If the agent is missing, the proxy will refuse to start with an "Unknown agent" error.

#### 2.8: Update build.sh

Edit `images/build.sh` to add:
- Default env var at top (e.g., `: "${GEMINI_VERSION:=latest}"`)
- Extra packages env var (e.g., `: "${GEMINI_EXTRA_PACKAGES:=}"`)
- `build_{agent}()` function following the pattern of existing agent build functions
- Add to the case statement (both specific target and `all` target)
- Update usage text (first line and examples)

#### 2.9: Agent Documentation

Create `docs/agents/{agent}.md` following this structure (see `docs/agents/codex.md` for exact format):

1. **Header**: `# {Display Name} Sandbox Template`
2. **One-liner**: "Run {display name} in a network-locked container..."
3. **Link**: "See the [main README](../../README.md) for installation, architecture overview, and configuration options."
4. **Setup section**: Auth instructions covering all supported auth methods. Note any gotchas (e.g., account-level settings that must be enabled).
5. **Usage section**: How to start the agent, including the auto-approve flag. Include `agentbox compose down` for stopping.
6. **Required Network Policy section**: Show the `services:` YAML snippet with the agent's service name.

#### 2.10: Update Project README

Edit `README.md`:
- Add row to the "Supported agents" table with the agent name, project URL, and status columns (CLI, VS Code, JetBrains). New agents are typically `:large_blue_circle: Preview` for CLI and devcontainer modes.
- Add link to `docs/{agent}/README.md` in the "Agent-specific setup" section

### Step 3: CI/CD Workflows

Create the CI files directly in `.github/workflows/`. They follow a clear pattern and can be written without drafting.

#### 3.1: Build Job

Edit `.github/workflows/build-images.yml`:
- Add `{AGENT}_IMAGE_NAME` env var (e.g., `GEMINI_IMAGE_NAME`)
- Add `build-{agent}` job following the pattern of `build-codex` (for GitHub releases) or `build-copilot` (for npm)
- Version detection depends on the source:
  - npm: `npm view {package} version`
  - GitHub releases: `gh api repos/{owner}/{repo}/releases/latest --jq .tag_name` with any tag prefix stripping via `sed`
- Add to summary job `needs` array
- Add agent version and digest to summary output table

#### 3.2: Version Check Workflow

Create `.github/workflows/check-{agent}-version.yml` following the pattern of existing version check workflows.

- Pick the next available daily cron slot (current: Claude 6am UTC, Copilot 7am, Codex 8am)
- Match the version source to the build job (npm or GitHub releases)
- Tag prefix: `{agent}-` for the GHCR tag check
- Trigger `build-images.yml` if the version tag doesn't exist in GHCR

### Step 4: Verify

After creating all files:

1. List all files created/modified
2. Note any manual steps needed
3. Remind user to:
   - Build and test locally: `./images/build.sh {agent}`
   - Verify the binary works: `docker run --rm agent-sandbox-{agent}:local {agent} --version`
   - Test init flow: `agentbox init --agent {agent} --mode cli --path /tmp/test-project`
   - Run CLI tests: `cli/run-tests.bash`
   - Test proxy enforcement after starting containers:
     - Allowed domain returns 200: `curl -x http://proxy:8080 https://{api-domain}`
     - Blocked domain returns 403: `curl -x http://proxy:8080 https://example.com`
   - Test auth flow inside the container

## Reference Files

When generating files, read these for the exact patterns:
- `images/agents/claude/Dockerfile` (npm install pattern)
- `images/agents/copilot/Dockerfile` (npm install with Node.js pattern)
- `images/agents/codex/Dockerfile` (direct binary download pattern, multi-arch, config file baking)
- `images/agents/codex/config.toml` (baked config file example)
- `cli/templates/compose/base.yml` (shared compose base layer with proxy and agent skeleton)
- `cli/templates/compose/mode.devcontainer.yml` (devcontainer mode overlay)
- `cli/templates/claude/cli/agent.yml` (agent compose layer with env vars)
- `cli/templates/copilot/cli/agent.yml` (simplest agent compose layer)
- `cli/templates/claude/devcontainer/devcontainer.json` (devcontainer with extensions and JetBrains plugins)
- `cli/templates/codex/devcontainer/devcontainer.json` (CLI-only agent, no extensions)
- `cli/lib/agent.bash` (agent registry: supported list, validation, selection)
- `cli/lib/cli-compose.bash` (CLI mode init flow, agent override scaffolding)
- `cli/lib/devcontainer.bash` (devcontainer mode init flow)
- `cli/test/init/init.bats` (init test assertion for agent list)
- `cli/test/switch/switch.bats` (switch test assertion for agent list)
- `images/proxy/addons/enforcer.py` (service domains, alphabetical ordering)
- `images/proxy/render-policy` (KNOWN_AGENTS set, policy rendering validation)
- `images/build.sh` (build functions and case statement)
- `docs/agents/codex.md` (simplest agent doc, CLI-only)
- `docs/agents/copilot.md` (agent doc with IDE notes)
- `README.md` (supported agents table and setup links)
- `.github/workflows/build-images.yml` (build jobs)
- `.github/workflows/check-codex-version.yml` (GitHub releases version check)
- `.github/workflows/check-copilot-version.yml` (npm version check)
