---
name: scaffold-agent
description: Scaffold all files needed to add a new agent to Agent Sandbox. Use when adding support for a new AI coding agent.
---

# Scaffold Agent Support

This skill generates all the files needed to add a new AI coding agent to Agent Sandbox. It follows the established patterns from Claude and Copilot implementations.

## Arguments

The skill takes a single argument: the agent name (lowercase, no spaces). Example: `codex`, `gemini`, `opencode`.

## Process

### Step 1: Gather Information

Ask the user for the following (skip any already provided):

1. **Agent name** (from argument)
2. **Display name** - human-readable name for comments and labels (e.g., "OpenAI Codex CLI")
3. **Installation method** - how to install the agent binary/CLI
   - npm package (like Claude and Copilot)
   - curl installer script
   - pip package
   - go install
   - direct binary download
4. **Package identifier** - npm package name, pip package, go module, or download URL
5. **Version variable name** - env var for build.sh (e.g., `CODEX_VERSION`)
6. **Config directory** - where the agent stores its config in the container (e.g., `/home/dev/.codex`)
7. **Required API domains** - domains the agent needs to reach (e.g., `api.openai.com`, `*.openai.com`)
8. **VS Code extension ID** - if one exists (e.g., `github.copilot-chat`)
9. **Agent-specific environment variables** - any env vars the agent needs at runtime
10. **Does the agent need Node.js?** - whether to install Node.js in the Dockerfile (only if the base image doesn't include it and the agent needs it)

### Step 2: Create Files

Generate all files listed below. Use the existing Claude and Copilot implementations as reference for the exact format and structure.

#### 2.1: Dockerfile

Create `images/agents/{agent}/Dockerfile`.

Pattern:
- `ARG BASE_IMAGE=agent-sandbox-base:local` + `FROM ${BASE_IMAGE}`
- Optional extra packages block (same pattern as existing agents)
- Install Node.js if needed (copy pattern from Copilot Dockerfile)
- Create config directory: `mkdir -p {config_dir} && chown -R dev:dev {config_dir}`
- Install the agent (method depends on installation type)
- Set version ARG for build tagging
- Add PATH if needed
- Add labels: `org.opencontainers.image.description` and version label

#### 2.2: CLI Compose Template

Create `cli/templates/{agent}/cli/docker-compose.yml`.

Copy from `cli/templates/copilot/cli/docker-compose.yml` and modify:
- Comment at top: `# {Display Name} Sandbox`
- Agent image: `ghcr.io/mattolson/agent-sandbox-{agent}:latest`
- State volume name: `{agent}-state` mounted at config directory
- History volume name: `{agent}-history`
- Agent-specific environment variables

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
- VS Code extension if applicable
- Keep proxy settings and JetBrains settings unchanged

#### 2.5: Update CLI Agent List

Edit `cli/libexec/init/init` line with `available_agents=` to add the new agent name to the array.

#### 2.6: Update Proxy Service Domains

Edit `images/proxy/addons/enforcer.py` to add a new entry to `SERVICE_DOMAINS` dict with the agent's required API domains.

#### 2.7: Update composefile.bash (if needed)

If the agent has host-side config that users might want to mount into the container (like Claude's `~/.claude/CLAUDE.md` and `settings.json`), add a conditional block in `cli/lib/composefile.bash` following the pattern of `add_claude_config_volumes`. This involves:
- Adding an `AGENTBOX_MOUNT_{AGENT}_CONFIG` env var check in `customize_compose_file()`
- Creating an `add_{agent}_config_volumes()` function
- Calling it conditionally when the agent matches

Skip this for agents that don't have meaningful host-side config to mount.

#### 2.8: Update build.sh

Edit `images/build.sh` to add:
- Default env var at top (e.g., `: "${CODEX_VERSION:=latest}"`)
- Extra packages env var (e.g., `: "${CODEX_EXTRA_PACKAGES:=}"`)
- `build_{agent}()` function following the pattern of existing agent build functions
- Add to the case statement (both specific target and `all` target)
- Update usage text

#### 2.9: Agent Documentation

Create `docs/{agent}/README.md` with:
- Brief description of the agent
- Link to official site/docs
- Any agent-specific setup notes
- Required API key or authentication details

### Step 3: Update CI/CD (draft only)

Create draft files that the user will commit from the host (CI files need to be tested):

#### 3.1: Build Job

Create `docs/plan/ci-drafts/{agent}-build-job.yml` containing the YAML snippet to add to `.github/workflows/build-images.yml`. Include:
- Environment variable for the image name
- Build job with version detection, metadata extraction, build and push
- Addition to summary job needs and table

#### 3.2: Version Check Workflow

Create `docs/plan/ci-drafts/check-{agent}-version.yml` containing the complete workflow file, following the pattern of `check-claude-version.yml`.

### Step 4: Verify

After creating all files:
1. List all files created/modified
2. Note any manual steps needed (CI files to apply, image to build, tests to run)
3. Remind user to:
   - Build and test locally: `./images/build.sh {agent}`
   - Test init flow: `agentbox init --agent {agent} --mode cli --path /tmp/test-project`
   - Apply CI drafts from `docs/plan/ci-drafts/` to `.github/workflows/`
   - Run CLI tests: `cli/run-tests.bash`

## Reference Files

When generating files, read these for the exact patterns:
- `images/agents/claude/Dockerfile`
- `images/agents/copilot/Dockerfile`
- `cli/templates/claude/cli/docker-compose.yml`
- `cli/templates/claude/devcontainer/docker-compose.yml`
- `cli/templates/claude/devcontainer/devcontainer.json`
- `cli/templates/copilot/cli/docker-compose.yml`
- `cli/templates/copilot/devcontainer/docker-compose.yml`
- `cli/templates/copilot/devcontainer/devcontainer.json`
- `cli/libexec/init/init`
- `images/proxy/addons/enforcer.py`
- `images/build.sh`
- `.github/workflows/build-images.yml`
- `.github/workflows/check-claude-version.yml`
