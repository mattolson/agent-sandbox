# Task: m3.5 - Git over HTTPS

**Status: Complete**

## Summary

Configure the container image so git operations work through the proxy. Port 22 is blocked, so git-over-SSH does not work. This task ensures git clone/push/pull work via HTTPS and documents credential setup options.

## Scope

- Add git URL rewrite config to base image (ssh -> https)
- Document credential caching options for users
- Test clone/push/pull through proxy
- Update documentation to explain HTTPS-only constraint

## Acceptance Criteria

- [x] `git clone git@github.com:...` automatically rewrites to HTTPS
- [x] `gh auth login` works from inside the container
- [x] `git push` works with cached credentials
- [x] README documents the HTTPS-only constraint
- [x] README documents credential setup options
- [x] README Security section warns about OAuth token scope (user-level, not repo-level)

## Applicable Learnings

- SSH allows tunneling which can bypass other network restrictions; blocking SSH entirely is simpler than restricting it
- Environment variable-based proxy configuration is advisory, not enforced; must combine with network-level enforcement
- Policy files must live outside workspace and be mounted read-only

## Plan

### Files Involved

**Modify:**
- `images/base/Dockerfile` - Add git config for URL rewriting
- `README.md` - Document HTTPS-only constraint and credential setup

### Approach

#### Phase 1: Git URL rewrite configuration

Add git config to the base image that rewrites SSH URLs to HTTPS. From decision 002:

```bash
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
```

Two options:
1. Run `git config` commands in Dockerfile as the dev user
2. Create a `.gitconfig` file and copy it to `/home/dev/.gitconfig`

Option 1 is simpler and keeps configuration visible in the Dockerfile.

Note: This only covers GitHub. Other git hosts (GitLab, Bitbucket) would need similar config. Start with GitHub only since that's the primary use case.

#### Phase 2: Documentation

Add a "Git configuration" section to README covering:

1. Git from host vs container: explain that git ops from host require no setup; container git is optional
2. HTTPS-only explanation: SSH (port 22) is blocked to prevent tunneling that could bypass the proxy
3. Automatic URL rewrite: `git@github.com:...` becomes `https://github.com/...`
4. Credential options (if using git inside container):
   - `gh auth login` - GitHub CLI handles OAuth, stores token, git can use it
   - Fine-grained PAT for repo-scoped access
   - User's own `.gitconfig` via dotfiles mount for custom credential helpers

Add to Security section:

- Git credentials inside the container are optional
- Users can run git operations (clone, commit, push) from the host instead
- This avoids giving the agent any git credentials at all
- If credentials are needed inside the container:
  - OAuth tokens from `gh auth login` are user-scoped, not repo-scoped
  - The token grants access to all repos the user can access, not just the current project
  - For tighter control: fine-grained PAT scoped to specific repos, or separate GitHub account

#### Phase 3: Testing

Manual tests to verify:
1. `git clone git@github.com:mattolson/agent-sandbox.git` works (rewrites to HTTPS)
2. `gh auth login` completes successfully
3. After auth, `git push` to an authorized repo works
4. Direct SSH fails: `ssh -T git@github.com` times out or is rejected

### Implementation Steps

- [x] Add git URL rewrite config to base Dockerfile
- [x] Rebuild base and agent images (from host: `./images/build.sh`)
- [x] Test URL rewrite: clone with ssh URL
- [x] Test `gh auth login` flow
- [x] Test push after auth
- [x] Add "Git configuration" section to README
- [x] Add credential scope warning to README Security section
- [x] Verify documentation accuracy

### Decisions

1. **GitHub only vs multiple hosts**: Start with GitHub. Users needing GitLab/Bitbucket can add their own config via dotfiles mount. Keeps the image focused.

2. **Where to add git config**: In Dockerfile using `git config --global`, not a separate file. Keeps it visible and auditable.

3. **Credential recommendation**: Lead with `gh auth login` since gh is already installed and it handles the OAuth flow cleanly. Mention credential-cache as fallback.
