# m1.3-policy-file

Extract hardcoded domains to policy.yaml and update firewall script to read from it.

Merged from original m1.3 (extract policy) and m1.4 (firewall reads policy).

## Goal

- Create a policy.yaml with the current allowlist
- Update init-firewall.sh to parse policy.yaml using yq
- Bake default policy into image; allow optional override via mount

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
  # npm
  - registry.npmjs.org
  # Claude Code
  - api.anthropic.com
  - sentry.io
  - statsig.anthropic.com
  - statsig.com
  # VS Code (devcontainer mode)
  - marketplace.visualstudio.com
  - mobile.events.data.microsoft.com
  - vscode.blob.core.windows.net
  - update.code.visualstudio.com
```

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

- [x] Create `images/base/policy.yaml`
- [x] Update `images/base/Dockerfile` to copy policy to `/etc/agent-sandbox/`
- [x] Update `images/base/init-firewall.sh` to read from policy file via yq
- [x] Add POLICY_FILE env var for override path (default: /etc/agent-sandbox/policy.yaml)
- [x] Test: default policy works
- [x] Test: firewall blocks non-allowlisted domains
- [x] Test: custom policy via mount works
- [x] Update README with policy override instructions
- [x] Update milestone plan (merge m1.3 and m1.4 references)

## Current State (for session resume)

**Status**: Complete.

**Branch**: `egress-policy`

**What's done**:
- policy.yaml created with default domains
- Dockerfile updated to copy policy to /etc/agent-sandbox/
- init-firewall.sh rewritten to parse policy via yq
- README updated with customization docs
- Milestone plan updated (merged m1.3+m1.4)
- All tests passing (default policy, blocking, custom override)

## Out of Scope

- Schema validation (trust the file format for now)
- Multiple policy files or includes
- Runtime policy reload without container restart

## Notes

- yq is already installed in base image (added in m1.2)
- Comments in YAML are allowed and encouraged for documentation
