# m1.3-policy-file

Extract hardcoded domains to policy.yaml and update firewall script to read from it.

Merged from original m1.3 (extract policy) and m1.4 (firewall reads policy).

## Goal

- Create a minimal policy.yaml for the base image
- Update init-firewall.sh to parse policy.yaml using yq
- Bake default policy into image; allow optional override via mount
- Create mode-specific policy overrides (devcontainer gets VS Code + Claude Code domains)

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

The base image contains a minimal policy. Mode-specific domains are added via overrides:

| Layer | File | Contents |
|-------|------|----------|
| Base image | `images/base/policy.yaml` | GitHub service only |
| Devcontainer | `.devcontainer/policy.yaml` | GitHub + VS Code + Claude Code |
| Claude Agent image | (future) | GitHub + Claude Code |

This keeps the base image agent-agnostic while allowing each mode to add what it needs.

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
- [x] Create `.devcontainer/policy.yaml` with VS Code + Claude Code domains
- [x] Update `.devcontainer/devcontainer.json` to mount policy override

## Current State (for session resume)

**Status**: Complete.

**Branch**: `egress-policy`

**What's done**:
- Base policy.yaml created (minimal: GitHub service only)
- Devcontainer policy override created (VS Code + Claude Code domains)
- Dockerfile updated to copy policy to /etc/agent-sandbox/
- devcontainer.json updated to mount policy override
- init-firewall.sh rewritten to parse policy via yq
- README updated with policy layering docs
- Milestone plan updated (merged m1.3+m1.4)
- All tests passing (default policy, blocking, custom override)

## Out of Scope

- Schema validation (trust the file format for now)
- Multiple policy files or includes
- Runtime policy reload without container restart

## Notes

- yq is already installed in base image (added in m1.2)
- Comments in YAML are allowed and encouraged for documentation
