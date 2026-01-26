# m4.1-copilot-support

Add GitHub Copilot CLI as a supported agent, following the multi-agent architecture from [Decision 003](../../../../decisions/003-separate-images-per-agent.md).

## Goal

A working Copilot CLI sandbox with:
- Agent image extending base
- Network policy allowing Copilot API domains
- Templates for both CLI and devcontainer modes
- Automated CI for version checking and image builds

## Implementation

### Files created

```
images/agents/copilot/
  Dockerfile           # Extends base, installs Copilot CLI via npm
  policy.yaml          # Default network policy for Copilot

templates/copilot/
  README.md            # Usage documentation
  docker-compose.yml   # CLI mode compose file
  .devcontainer/
    devcontainer.json  # VS Code devcontainer config
    docker-compose.yml # Devcontainer mode compose file

docs/policy/examples/
  copilot.yaml         # CLI policy (GitHub + Copilot)
  copilot-devcontainer.yaml  # Devcontainer policy (adds VS Code)

.github/workflows/
  check-copilot-version.yml  # Daily check for new Copilot CLI versions
```

### Files modified

```
.github/workflows/build-images.yml  # Add build-copilot job
images/proxy/addons/enforcer.py     # Add copilot service domains
docs/policy/schema.md               # Document copilot service
README.md                           # Multi-agent overview
ROADMAP.md                          # Update m4 progress
```

### Copilot image (Dockerfile)

```dockerfile
ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Install Node.js and Copilot CLI
USER root
COPY policy.yaml /etc/agent-sandbox/policy.yaml
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/dev/.copilot && chown -R dev:dev /home/dev/.copilot

ARG COPILOT_VERSION=latest
RUN npm install -g @github/copilot@${COPILOT_VERSION}

USER dev
```

Key differences from Claude image:
- Requires Node.js for npm
- Copilot CLI installed via npm (not pip)
- Credentials stored in `~/.copilot` (not `~/.claude`)

### Proxy enforcer domains

Added `copilot` service to `SERVICE_DOMAINS` in `enforcer.py`:

```python
"copilot": [
    "*.githubcopilot.com",
    "copilot-proxy.githubusercontent.com",
    "*.exp-tas.com",
    "*.githubassets.com",
],
```

Domains discovered by running Copilot in discovery mode and observing traffic.

### CI workflows

**build-images.yml** changes:
- Added `COPILOT_IMAGE_NAME` env var
- Added `build-copilot` job (parallel to build-claude, depends on build-base)
- Updated summary job to include Copilot digest

**check-copilot-version.yml** (new):
- Runs daily at 7am UTC (offset from Claude's 6am check)
- Fetches latest version from `npm view @github/copilot@latest version`
- Checks if `copilot-{version}` tag exists in GHCR
- Triggers build-images workflow if tag missing

### Templates

Two compose files, matching Claude template structure:

- `docker-compose.yml`: CLI mode, mounts `policies/copilot.yaml`
- `.devcontainer/docker-compose.yml`: VS Code mode, mounts `policies/copilot-vscode.yaml`

Separate compose files allow CLI and devcontainer modes to run simultaneously without container/volume name conflicts.

## Testing

Validated locally before creating plan:

1. Built images: `./images/build.sh`
2. Started CLI mode: `cd templates/copilot && docker compose up -d`
3. Authenticated: `docker compose exec agent zsh -i -c 'copilot'` → `/login`
4. Verified sandbox:
   - `curl https://api.github.com/zen` → allowed
   - `curl https://example.com` → 403 blocked
   - `curl --noproxy '*' https://example.com` → timeout (iptables blocked)
5. Tested Copilot CLI functionality with `/help`, basic prompts

## Checklist

- [x] `images/agents/copilot/Dockerfile` - extends base, installs Copilot CLI
- [x] `images/agents/copilot/policy.yaml` - default network policy
- [x] `images/proxy/addons/enforcer.py` - add `copilot` service domains
- [x] `docs/policy/examples/copilot.yaml` - CLI policy example
- [x] `docs/policy/examples/copilot-devcontainer.yaml` - devcontainer policy example
- [x] `docs/policy/schema.md` - document copilot service
- [x] `templates/copilot/docker-compose.yml` - CLI mode
- [x] `templates/copilot/.devcontainer/devcontainer.json` - VS Code config
- [x] `templates/copilot/.devcontainer/docker-compose.yml` - devcontainer mode
- [x] `templates/copilot/README.md` - usage documentation
- [x] `.github/workflows/build-images.yml` - add build-copilot job
- [x] `.github/workflows/check-copilot-version.yml` - version check workflow
- [x] `README.md` - update for multi-agent support
- [x] `ROADMAP.md` - update m4 progress

## Definition of Done

- [x] Copilot CLI image builds successfully
- [x] Copilot CLI authenticates and responds to prompts
- [x] Network policy blocks unauthorized domains
- [x] iptables blocks direct outbound (proxy bypass prevented)
- [x] Templates work for both CLI and devcontainer modes
- [x] CI workflows trigger builds on new Copilot versions
- [x] Documentation updated
