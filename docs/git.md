# Git Configuration

Git operations can be run from the host or from inside the container.

## Git from host (recommended)

Run git commands (clone, commit, push) from your host terminal. The agent writes code, you handle version control. No credential setup needed inside the container.

## Git from container

If you want the agent to run git commands, some setup is required.

**SSH is blocked.** Port 22 is blocked to prevent SSH tunneling, which could bypass the proxy. The container automatically rewrites SSH URLs to HTTPS:

```
git@github.com:user/repo.git -> https://github.com/user/repo.git
```

**Credential setup.** To push or access private repos, create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to specific repositories. Then configure git to store it:

```bash
git config --global credential.helper store
```

On the next `git push` or `git pull` against a private repo, git will prompt for your username and token. Enter your GitHub username and paste the PAT as the password. The credential is saved to `~/.git-credentials` and reused automatically from then on.

Credentials are stored in plaintext on disk inside the container. The file persists in the agent's Docker volume across rebuilds. See the [security section](../README.md#git-credentials) for ways to limit exposure.
