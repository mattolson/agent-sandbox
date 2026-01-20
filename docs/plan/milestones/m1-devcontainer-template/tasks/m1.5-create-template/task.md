# m1.5-create-template

Create the minimal/claude template structure with both runtime modes.

## Goal

Create a ready-to-copy template at `devcontainer/templates/minimal/claude/` that users can drop into their projects to get a sandboxed Claude Code environment.

## Template Structure

```
devcontainer/templates/minimal/claude/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── policy.yaml
└── docker-compose.yml
```

Note: policy.yaml lives in .devcontainer/ so the Dockerfile can COPY it. Docker build context can't access parent directories.

READMEs are added in m1.6.

## Design Decisions

### Policy: Include VS Code domains?

**Decision**: Yes. The template is primarily for devcontainer use, so include VS Code domains. Compose-only users can remove them.

### Dockerfile: Required or optional?

**Decision**: Required. Even though we could reference the image directly in devcontainer.json, having a Dockerfile:
- Makes the policy.yaml override work (COPY into image)
- Gives users a place to add project-specific customizations
- Matches the pattern from our development setup

### Image reference: Local or GHCR?

**Decision**: Local for now (`agent-sandbox-claude:local`). M2 will update to GHCR with digest pinning.

Users must run `./images/build.sh` from the agent-sandbox repo before using the template. This is documented in m1.6.

### Volume naming

Use `${devcontainerId}` for project-scoped volumes. This ID is stable across rebuilds and unique per project, unlike folder names which can change.

## Implementation Plan

### 1. Create directory structure

```bash
mkdir -p devcontainer/templates/minimal/claude/.devcontainer
```

### 2. Create policy.yaml

Copy from `.devcontainer/policy.yaml` - includes GitHub, Claude Code, and VS Code.

### 3. Create Dockerfile

Minimal Dockerfile that:
- Uses `agent-sandbox-claude:local` as base
- Copies policy.yaml to `/etc/agent-sandbox/policy.yaml`

### 4. Create devcontainer.json

Based on current `.devcontainer/devcontainer.json` but:
- Generic name ("Claude Code Sandbox")
- Use `${localWorkspaceFolderBasename}` for volume names
- Remove agent-sandbox-specific settings
- Keep essential mounts (claude state, history, host claude config)

### 5. Create docker-compose.yml

Based on current `docker-compose.yml` but:
- Reference the template's policy.yaml
- Use project-name-based volume names
- Add comments for customization

## Tasks

- [x] Create directory structure
- [x] Create policy.yaml
- [x] Create Dockerfile
- [x] Create devcontainer.json
- [x] Create docker-compose.yml
- [ ] Test: devcontainer mode works
- [ ] Test: compose mode works

## Notes

- The template uses local images for now. Users need access to the agent-sandbox repo to build images.
- M2 will publish images to GHCR, making the template truly standalone.
