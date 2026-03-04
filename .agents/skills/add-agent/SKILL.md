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
15. **Agent-specific environment variables** - any env vars the agent needs at runtime
16. **Does the agent need Node.js?** - whether to install Node.js in the Dockerfile (only if the base image doesn't include it and the agent needs it)

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

#### 2.2: CLI Compose Template

Create `cli/templates/{agent}/cli/docker-compose.yml`.

Copy from an existing CLI template (Copilot is simplest) and modify:
- Comment at top: `# {Display Name} Sandbox`
- Agent image: `ghcr.io/mattolson/agent-sandbox-{agent}:latest`
- State volume: `{agent}-state` mounted at config directory
- History volume: `{agent}-history`
- Agent-specific environment variables
- Always include `GODEBUG=http2client=0` (workaround for Go programs through mitmproxy)
- Always include `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` settings
- Update the named volumes section at the bottom

#### 2.3: Devcontainer Compose Template

Create `cli/templates/{agent}/devcontainer/docker-compose.yml`.

Same as CLI template but add the devcontainer directory mount:
```yaml
- .:/workspace/.devcontainer:ro
```

#### 2.4: devcontainer.json

Create `cli/templates/{agent}/devcontainer/devcontainer.json`.

Copy from existing and modify:
- `name`: `"{Display Name} Sandbox"`
- VS Code extensions array if applicable, or remove extensions arrays for CLI-only agents
- Keep proxy settings and JetBrains settings unchanged

#### 2.5: Update CLI Agent List

Edit `cli/libexec/init/init`: add the new agent name to the `available_agents` array.

#### 2.6: Update BATS Test

Edit `cli/test/init/init.bats`: update the "rejects invalid --agent value" test assertion to include the new agent name in the expected agent list string (e.g., `"claude copilot codex gemini"`).

#### 2.7: Update Proxy Service Domains

Edit `images/proxy/addons/enforcer.py`: add a new entry to `SERVICE_DOMAINS` dict.

Guidelines:
- Place alphabetically among existing entries
- Prefer wildcards over listing subdomains individually (e.g., `*.openai.com` covers `api.openai.com`, `auth.openai.com`, regional endpoints)
- Only use separate entries for different TLDs (e.g., `chatgpt.com` is separate from `openai.com`)
- Include both API domains and auth/OAuth domains so authentication works through the proxy

#### 2.8: Update composefile.bash (if needed)

If the agent has host-side config that users might want to mount into the container (like Claude's `~/.claude/CLAUDE.md` and `settings.json`), add a conditional block in `cli/lib/composefile.bash` following the pattern of `add_claude_config_volumes`. This involves:
- Adding an `AGENTBOX_MOUNT_{AGENT}_CONFIG` env var check in `customize_compose_file()`
- Creating an `add_{agent}_config_volumes()` function
- Calling it conditionally when the agent matches

Skip this for agents that don't have meaningful host-side config to mount.

#### 2.9: Update build.sh

Edit `images/build.sh` to add:
- Default env var at top (e.g., `: "${GEMINI_VERSION:=latest}"`)
- Extra packages env var (e.g., `: "${GEMINI_EXTRA_PACKAGES:=}"`)
- `build_{agent}()` function following the pattern of existing agent build functions
- Add to the case statement (both specific target and `all` target)
- Update usage text (first line and examples)

#### 2.10: Agent Documentation

Create `docs/{agent}/README.md` following this structure (see `docs/copilot/README.md` or `docs/codex/README.md` for exact format):

1. **Header**: `# {Display Name} Sandbox Template`
2. **One-liner**: "Run {display name} in a network-locked container..."
3. **Link**: "See the [main README](../../README.md) for installation, architecture overview, and configuration options."
4. **Setup section**: Auth instructions covering all supported auth methods. Note any gotchas (e.g., account-level settings that must be enabled).
5. **Usage section**: How to start the agent, including the auto-approve flag. Include `agentbox compose down` for stopping.
6. **Required Network Policy section**: Show the `services:` YAML snippet with the agent's service name.

#### 2.11: Update Project README

Edit `README.md`:
- Add row to the "Supported agents" table with the agent name, project URL, and status (usually `Preview` for new agents)
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
- `cli/templates/copilot/cli/docker-compose.yml` (simplest CLI template)
- `cli/templates/codex/cli/docker-compose.yml` (CLI template with agent-specific env vars)
- `cli/templates/copilot/devcontainer/docker-compose.yml`
- `cli/templates/copilot/devcontainer/devcontainer.json`
- `cli/templates/codex/devcontainer/devcontainer.json` (CLI-only agent, no extensions)
- `cli/libexec/init/init` (agent list)
- `cli/test/init/init.bats` (test assertion for agent list)
- `images/proxy/addons/enforcer.py` (service domains, alphabetical ordering)
- `images/build.sh` (build functions and case statement)
- `docs/codex/README.md` (simplest agent doc, CLI-only)
- `docs/copilot/README.md` (agent doc with IDE notes)
- `README.md` (supported agents table and setup links)
- `.github/workflows/build-images.yml` (build jobs)
- `.github/workflows/check-codex-version.yml` (GitHub releases version check)
- `.github/workflows/check-copilot-version.yml` (npm version check)
