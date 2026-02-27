# Agent Switching via Symlinks

## Context

Users want to try different AI coding agents without losing their setup. Today, `agentbox init` locks a project to one agent. Trying another means destroying and re-initializing, which loses volume state and all customizations to compose, policy, and devcontainer files.

This adds `agentbox switch <agent>` using symlinks. Each agent gets its own complete config files. A symlink points to the active one. Switching swaps the symlink. No YAML surgery, no risk of losing edits. Docker named volumes persist across switches, so agent state (credentials, history) is preserved.

## Directory Layout

All files stay flat in `.agent-sandbox/` (same directory = no relative path resolution issues):

```
.agent-sandbox/
  docker-compose.yml -> docker-compose.claude.yml   (symlink to active)
  docker-compose.claude.yml                          (Claude's compose, fully editable)
  docker-compose.copilot.yml                         (Copilot's compose, created on first switch)
  policy.yaml -> policy.claude.yaml                  (symlink to active)
  policy.claude.yaml                                 (Claude's policy, fully editable)
  policy.copilot.yaml                                (Copilot's policy, created on first switch)
```

Docker Compose receives the symlink path via `-f`. Since target and symlink are in the same directory, relative paths resolve identically regardless of symlink traversal behavior.

The proxy mounts `policy.yaml` (the symlink). Docker resolves it to the actual file at container start time.

## Changes

### 1. Update `agentbox init` to create symlink layout

**File: `cli/libexec/init/init`**

Policy file path changes:
```bash
# Before
local policy_file="$AGB_PROJECT_DIR/policy-$mode-$agent.yaml"

# After
local policy_file="$AGB_PROJECT_DIR/policy.$agent.yaml"
local policy_link="$AGB_PROJECT_DIR/policy.yaml"
```

After creating the policy file, create symlink:
```bash
ln -s "policy.$agent.yaml" "$project_path/$policy_link"
```

Pass the symlink name (not the real file) to the cli/devcontainer subcommand so the compose file mounts the symlink.

**File: `cli/libexec/init/cli`**

Compose file naming changes:
```bash
# Before
local compose_file="$compose_dir/docker-compose.yml"
cp "$AGB_TEMPLATEDIR/$agent/cli/docker-compose.yml" "$compose_dir"

# After
local compose_file="$compose_dir/docker-compose.$agent.yml"
cp "$AGB_TEMPLATEDIR/$agent/cli/docker-compose.yml" "$compose_file"
ln -s "docker-compose.$agent.yml" "$compose_dir/docker-compose.yml"
```

The `customize_compose_file` call operates on the real file (`docker-compose.$agent.yml`). The symlink (`docker-compose.yml`) is what `find_compose_file` and `run-compose` discover.

### 2. New command: `agentbox switch <agent>`

**New file: `cli/libexec/switch/switch`**

```bash
switch() {
    # 1. Validate agent name
    # 2. Find compose dir via find_compose_file -> dirname
    # 3. Read current agent from symlink target:
    #    readlink docker-compose.yml -> docker-compose.claude.yml -> "claude"
    # 4. Validate not already on requested agent
    # 5. Check if containers running, stop if so (docker compose down)
    # 6. If first time for this agent (docker-compose.$agent.yml doesn't exist):
    #    a. Copy template from $AGB_TEMPLATEDIR/$agent/cli/docker-compose.yml
    #    b. Run customize_compose_file (pin images, add policy mount, optional volumes)
    #    c. Copy project name from current compose file
    #    d. Create policy.$agent.yaml via the policy subcommand
    # 7. Swap symlinks:
    #    ln -sf "docker-compose.$agent.yml" docker-compose.yml
    #    ln -sf "policy.$agent.yaml" policy.yaml
    # 8. If containers were running, start new agent (docker compose up -d)
    # 9. Print: "Switched from claude to copilot"
}
```

Dependencies: sources `composefile.bash`, `path.bash`, `logging.bash`, `require.bash`, `constants.bash`. Uses `find_compose_file()`, `customize_compose_file()`, `set_project_name()`, `pull_and_pin_image()`.

The policy symlink path for the proxy volume mount is already correct since all compose files reference the same symlink name (`policy.yaml`). The `add_policy_volume` call during first-time setup receives the symlink path.

### 3. Update `agentbox edit policy` for new naming

**File: `cli/libexec/edit/policy`**

Current glob: `policy-$mode-$agent.yaml` (line 49)

Updated logic:
1. Look for `policy.yaml` symlink in `.agent-sandbox/` first
2. If found, resolve it (`readlink -f`) and open the target
3. If not found, fall back to old glob pattern (`policy-*-*.yaml`) for backward compat

### 4. Extract available_agents to shared location

**New file: `cli/lib/agents.bash`**

Contains the `available_agents` array and a helper to detect the current agent from the compose symlink:

```bash
available_agents=(claude copilot codex)

# Reads current agent from the compose file symlink target name
# e.g., docker-compose.claude.yml -> "claude"
current_agent() {
    local compose_dir=$1
    local link="$compose_dir/docker-compose.yml"
    if [[ -L "$link" ]]; then
        local target
        target=$(readlink "$link")
        # Extract agent from docker-compose.{agent}.yml
        target=${target#docker-compose.}
        target=${target%.yml}
        echo "$target"
    else
        # Legacy: no symlink, try to infer from image name
        local image
        image=$(yq '.services.agent.image' "$compose_dir/docker-compose.yml")
        # ghcr.io/.../agent-sandbox-claude@sha256:... -> claude
        image=${image##*agent-sandbox-}
        image=${image%%[@:]*}
        echo "$image"
    fi
}
```

Source this from `init/init` (replaces inline array) and `switch/switch`.

## Files Summary

| Action | File | Purpose |
|--------|------|---------|
| Create | `cli/lib/agents.bash` | Shared agent list, current_agent() helper |
| Create | `cli/libexec/switch/switch` | `agentbox switch` command |
| Modify | `cli/libexec/init/init` | New policy naming, create policy symlink, source agents.bash |
| Modify | `cli/libexec/init/cli` | Per-agent compose filename, create compose symlink |
| Modify | `cli/libexec/edit/policy` | Find policy via symlink first, fall back to old glob |

## Unchanged

- `cli/lib/composefile.bash` - service name stays `agent`, no changes
- `cli/libexec/exec/exec` - still targets `agent` service via symlinked compose file
- `cli/libexec/bump/bump` - still targets `proxy` and `agent`
- `cli/lib/run-compose` - `find_compose_file` returns the symlink path, works transparently
- `cli/lib/path.bash` - `find_compose_file` finds `docker-compose.yml` (the symlink), no change
- `cli/templates/*/cli/docker-compose.yml` - templates unchanged
- `cli/templates/*/devcontainer/*` - out of scope for now (same pattern applies later)

## Edge Cases

- **First switch to new agent**: Compose file generated from template. User starts with default config, can customize it. Switching back to original agent restores all their edits.
- **Existing projects (pre-symlink)**: `switch` detects non-symlink `docker-compose.yml`, renames it to `docker-compose.$current.yml`, creates the symlink. Same for policy.
- **Switch to same agent**: Detect from symlink target, print message, exit 0.
- **Containers not running**: Just swap symlinks, skip down/up.
- **Policy customizations carry over?**: No. Each agent has its own policy file. First-time creation uses a basic template. The user edits each agent's policy independently. This is correct - different agents need different service allowlists.
- **Compose customizations carry over?**: No. First-time creation starts from the template. Shared preferences (dotfiles, shell customizations) can be set via `AGENTBOX_*` env vars so they apply to all agents during first-time setup. Direct compose edits are per-agent.
- **`docker compose down --volumes`**: This would destroy volumes. `switch` uses plain `down` (no `--volumes`). Document this for users.
- **Git and symlinks**: Git handles symlinks natively on Linux/macOS (primary target platform).

## Implementation Order

1. Create `cli/lib/agents.bash`
2. Update `cli/libexec/init/init` (policy naming + symlink)
3. Update `cli/libexec/init/cli` (compose naming + symlink)
4. Update `cli/libexec/edit/policy` (symlink-aware discovery)
5. Create `cli/libexec/switch/switch`
6. Test end-to-end

## Verification

1. `agentbox init --agent claude --mode cli --name test` in a temp directory:
   - Creates `docker-compose.claude.yml` and symlink `docker-compose.yml -> docker-compose.claude.yml`
   - Creates `policy.claude.yaml` and symlink `policy.yaml -> policy.claude.yaml`
   - Proxy volume mounts `policy.yaml` (the symlink)
2. Manually edit the compose file (uncomment a volume). Verify the edit persists in `docker-compose.claude.yml`.
3. `agentbox switch copilot`:
   - Creates `docker-compose.copilot.yml` from template
   - Creates `policy.copilot.yaml` from template
   - Symlinks updated: `docker-compose.yml -> docker-compose.copilot.yml`, `policy.yaml -> policy.copilot.yaml`
4. `agentbox switch claude`:
   - Symlinks point back to claude files
   - Manual edit from step 2 is still there
5. `agentbox edit policy` opens the correct file
6. `cli/run-tests.bash` passes
