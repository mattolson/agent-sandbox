# m1.3-policy-file

Extract hardcoded domains to policy.yaml and update firewall script to read from it.

Merged from original m1.3 (extract policy) and m1.4 (firewall reads policy).

## Goal

- Create policy.yaml files for each image layer with appropriate defaults
- Update init-firewall.sh to parse policy.yaml using yq
- Bake default policies into images so things work out of the box
- Support optional override via mount from host filesystem (outside workspace) for security

## Security Model

**Threat**: Agent modifies policy file, re-runs firewall, exfiltrates data.

**Mitigation**:
- Default policy baked into image at `/etc/agent-sandbox/policy.yaml` (owned by root, not writable by dev)
- Agent cannot modify baked-in policy
- Optional override via read-only mount from host (outside workspace)
- Even if agent re-runs script, it reads the same immutable policy

**Safe because**:
- Policy file is outside workspace (agent can't write to it)
- Mounted read-only if overridden
- Re-running firewall just re-applies same rules

## Policy Schema

```yaml
# /etc/agent-sandbox/policy.yaml
services:
  - github  # special handling: fetches IPs from api.github.com/meta

domains:
  - example.com
  # ... additional domains
```

## Policy Layering

Each image layer includes a default policy with the domains it needs. Everything works out of the box.

| Image | Policy file | Domains |
|-------|-------------|---------|
| Base | `images/base/policy.yaml` | GitHub only |
| Claude agent | `images/agents/claude/policy.yaml` | GitHub + Claude Code |
| Devcontainer | `.devcontainer/policy.yaml` | GitHub + Claude Code + VS Code |

Each layer's Dockerfile copies its policy to `/etc/agent-sandbox/policy.yaml`, overwriting the parent.

**Optional customization**: Users can mount their own policy from `~/.config/agent-sandbox/policy.yaml` to override the baked-in default.

**Security constraint**: Custom policies must come from host filesystem, not workspace. If policy were in the workspace, the agent could modify it and re-run the firewall to allow exfiltration. Baked-in policies are safe because the agent cannot modify the image.

## Implementation Plan

### 1. Create default policy file

Create `images/base/policy.yaml` with current hardcoded domains.

### 2. Update Dockerfile to install policy

```dockerfile
# Copy policy file
COPY policy.yaml /etc/agent-sandbox/policy.yaml
RUN chmod 644 /etc/agent-sandbox/policy.yaml
```

### 3. Update init-firewall.sh to read policy

Replace hardcoded domains with yq parsing:

```bash
POLICY_FILE="${POLICY_FILE:-/etc/agent-sandbox/policy.yaml}"

# Read services
for service in $(yq -r '.services[]' "$POLICY_FILE"); do
  case "$service" in
    github)
      # existing github-meta logic
      ;;
    *)
      echo "WARNING: Unknown service: $service"
      ;;
  esac
done

# Read domains
for domain in $(yq -r '.domains[]' "$POLICY_FILE"); do
  # existing DNS resolution logic
done
```

### 4. Document override mechanism

Users can override by mounting their own policy:

**docker-compose.yml:**
```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/policy.yaml:/etc/agent-sandbox/policy.yaml:ro
```

**devcontainer.json:**
```json
"mounts": [
  "source=${localEnv:HOME}/.config/agent-sandbox/policy.yaml,target=/etc/agent-sandbox/policy.yaml,type=bind,readonly"
]
```

### 5. Rebuild and test

- Verify default policy works without any mount
- Verify custom policy works with mount
- Verify agent cannot modify policy (permission denied)

## Tasks

- [x] Create `images/base/policy.yaml` (minimal: GitHub only)
- [x] Update `images/base/Dockerfile` to copy policy to `/etc/agent-sandbox/`
- [x] Update `images/base/init-firewall.sh` to read from policy file via yq
- [x] Add POLICY_FILE env var for override path (default: /etc/agent-sandbox/policy.yaml)
- [x] Test: default policy works
- [x] Test: firewall blocks non-allowlisted domains
- [x] Test: custom policy via mount works
- [x] Update README with policy override instructions
- [x] Update milestone plan (merge m1.3 and m1.4 references)
- [x] Create `images/agents/claude/policy.yaml` (GitHub + Claude Code)
- [x] Update `images/agents/claude/Dockerfile` to copy policy
- [x] Create `.devcontainer/policy.yaml` (GitHub + VS Code + Claude Code)
- [x] Update `.devcontainer/Dockerfile` to copy policy

## Current State (for session resume)

**Status**: Complete.

**Branch**: `egress-policy`

**What's done**:
- Policy layering implemented across all images
- Base: GitHub only
- Claude agent: GitHub + Claude Code (api.anthropic.com, sentry.io, statsig.*)
- Devcontainer: GitHub + Claude Code + VS Code (marketplace, updates, telemetry)
- init-firewall.sh parses policy via yq
- Optional host override supported via mount from ~/.config/agent-sandbox/
- README updated with policy documentation
- All images work out of the box with no configuration required

## Out of Scope

- Schema validation (trust the file format for now)
- Multiple policy files or includes
- Runtime policy reload without container restart

## Notes

- yq is already installed in base image (added in m1.2)
- Comments in YAML are allowed and encouraged for documentation
