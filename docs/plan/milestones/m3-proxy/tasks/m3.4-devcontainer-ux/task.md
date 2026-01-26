# Task: m3.4 - Devcontainer UX

## Summary

Validate and refine the devcontainer experience using this repo as the test case. Split compose files to isolate CLI and devcontainer modes, add VS Code service domains, and ensure both can run simultaneously without conflicts.

## Scope

- Add `vscode` service to proxy SERVICE_DOMAINS
- Create separate compose files for CLI vs devcontainer modes
- Migrate this repo's `.devcontainer/` to use compose backend with proxy
- Create policy examples for both modes
- Update templates to match validated structure
- Cleanup: update docs, remove old code paths

## Acceptance Criteria

- [x] Devcontainer opens in VS Code with proxy enforcement working
- [x] CLI compose and devcontainer can run simultaneously (no name conflicts)
- [x] VS Code extensions install/update without being blocked
- [x] Firewall blocks direct outbound (bypassing proxy)
- [x] Template structure matches this repo's validated setup
- [x] Documentation reflects the new architecture

## Applicable Learnings

- VS Code devcontainers bypass Docker ENTRYPOINT; use `postStartCommand` for runtime init
- Devcontainers can use Docker Compose backend via `dockerComposeFile` in devcontainer.json
- Policy files must live outside workspace and be mounted read-only
- `${devcontainerId}` variable can namespace resources in devcontainer.json mounts

## Plan

### Files Involved

**Modify:**
- `images/proxy/addons/enforcer.py` - Add vscode to SERVICE_DOMAINS
- `.devcontainer/devcontainer.json` - Switch to dockerComposeFile backend
- `templates/claude/.devcontainer/devcontainer.json` - Point to local compose file
- `templates/claude/docker-compose.yml` - CLI-only mode
- `templates/claude/README.md` - Document both modes clearly
- `.claude/CLAUDE.md` - Update architecture description
- `README.md` - Update with proxy-based setup

**Create:**
- `.devcontainer/docker-compose.yml` - Devcontainer-specific compose with namespaced resources
- `templates/claude/.devcontainer/docker-compose.yml` - Devcontainer compose for template
- `docs/policy/examples/claude-devcontainer.yaml` - Policy with vscode service

**Delete:**
- `.devcontainer/Dockerfile` - No longer needed, use pre-built image
- `.devcontainer/policy.yaml` - Policy now baked into proxy image or mounted from host

### Approach

#### Phase 1: Proxy vscode service

Add VS Code domains to SERVICE_DOMAINS in enforcer.py. Domains needed:
- update.code.visualstudio.com
- marketplace.visualstudio.com
- vscode.blob.core.windows.net
- *.vsassets.io (extensions CDN)
- *.gallerycdn.vsassets.io (gallery assets)
- mobile.events.data.microsoft.com (telemetry, may be optional)

#### Phase 2: This repo's devcontainer

Create `.devcontainer/docker-compose.yml` with:
- Namespaced container names: `agent-sandbox-devcontainer`, `agent-sandbox-devcontainer-proxy`
- Volume names get auto-prefixed by compose project name
- Mount devcontainer-specific policy from host or use baked-in with vscode service
- Use local images (`agent-sandbox-claude:local`, build proxy from `./images/proxy`)

Update `.devcontainer/devcontainer.json`:
- Remove `build` section
- Add `dockerComposeFile: docker-compose.yml`
- Add `service: agent`
- Keep VS Code settings and remoteUser

Delete old files:
- `.devcontainer/Dockerfile`
- `.devcontainer/policy.yaml`

Test the full workflow:
1. Rebuild images with `./images/build.sh`
2. Open in VS Code via "Reopen in Container"
3. Verify proxy logs show traffic
4. Verify blocked domains return 403
5. Verify VS Code extensions work

#### Phase 3: Template updates

Update `templates/claude/` to match the validated structure:
- `.devcontainer/devcontainer.json` points to `./docker-compose.yml`
- `.devcontainer/docker-compose.yml` with namespaced resources, published images
- Root `docker-compose.yml` for CLI usage with different container names
- Clear README explaining both modes

#### Phase 4: Policy examples

- Keep `docs/policy/examples/claude.yaml` as CLI policy (no vscode)
- Create `docs/policy/examples/claude-devcontainer.yaml` with `services: [github, vscode]`

#### Phase 5: Documentation and cleanup

- Update `.claude/CLAUDE.md` with current architecture
- Update root `README.md` with proxy-based setup
- Verify no old iptables-only code paths remain in use

### Implementation Steps

- [x] Add vscode service to SERVICE_DOMAINS in enforcer.py
- [x] Create `.devcontainer/docker-compose.yml` with namespaced resources
- [x] Update `.devcontainer/devcontainer.json` for compose backend
- [x] Delete `.devcontainer/Dockerfile` and `.devcontainer/policy.yaml`
- [x] Create `docs/policy/examples/claude-devcontainer.yaml`
- [x] Test devcontainer workflow in VS Code
- [x] Test CLI compose still works alongside devcontainer
- [x] Create `templates/claude/.devcontainer/docker-compose.yml`
- [x] Update `templates/claude/.devcontainer/devcontainer.json`
- [x] Update `templates/claude/docker-compose.yml` for CLI-only
- [x] Update `templates/claude/README.md`
- [x] Update `.claude/CLAUDE.md`
- [x] Update root `README.md`

### Decisions

1. **VS Code domain coverage**: Start with known domains, add as needed during testing.

2. **Container naming**: Use dynamic naming via compose project name. Remove explicit `container_name` directives so compose auto-generates names like `projectname-proxy-1`, `projectname-agent-1`. Volumes are already auto-prefixed.

3. **Policy strategy**:
   - Proxy image bakes in tight default (`services: [github]` only)
   - Devcontainer usage requires mounting policy from host (`~/.config/agent-sandbox/policy.yaml`)
   - Provide example policies in `docs/policy/examples/` for users to copy
   - This keeps policy outside workspace for security
