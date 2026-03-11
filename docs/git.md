# Git Configuration

Git operations can be run from the host or from inside the container.

## Git from host (recommended)

Run git commands (clone, commit, push) from your host terminal. The agent writes code, you handle version control. No credential setup needed inside the container.

## Worktrees across host and container

Git worktree metadata breaks if it stores container-only absolute paths such as `/workspace/.worktrees/feature` and the host sees the same repo at a different path.

The base image avoids that by:

- Shipping Git 2.50.1 by default
- Setting `worktree.useRelativePaths=true` in the container's system git config (`/usr/local/etc/gitconfig`)

Practical guidance:

- Create shared worktrees under the repo root, for example `.worktrees/feature`
- Use Git 2.48 or newer on the host as well when working with repos that use relative worktree metadata
- On macOS, prefer Homebrew Git over the older Apple-provided Git when using this workflow

Why this is necessary: Debian bookworm's packaged Git is 2.39.5, and that version cannot create relative worktree metadata with config alone.

If you already created worktrees with older container images, recreate them or repair them from a Git 2.48+ environment before expecting host/container path portability.

## Git from container

If you want the agent to run git commands, some setup is required.

**SSH is blocked.** Port 22 is blocked to prevent SSH tunneling, which could bypass the proxy. The container automatically rewrites SSH URLs to HTTPS:

```
git@github.com:user/repo.git -> https://github.com/user/repo.git
```

Those defaults live in the container's system git config (`/usr/local/etc/gitconfig`), so mounting your own `~/.gitconfig` via dotfiles does not replace them.

**Credential setup.** To push or access private repos, create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to specific repositories. Then configure git to store it:

```bash
git config --global credential.helper store
```

On the next `git push` or `git pull` against a private repo, git will prompt for your username and token. Enter your GitHub username and paste the PAT as the password. The credential is saved to `~/.git-credentials` and reused automatically from then on.

Credentials are stored in plaintext on disk inside the container. The file persists in the agent's Docker volume across rebuilds. See the [security section](../README.md#git-credentials) for ways to limit exposure.

## Git identity

The container does not have access to your host's global gitconfig. Git commits will fail with:

```
Author identity unknown
*** Please tell me who you are.
```

Two ways to fix this:

**Mount your gitconfig via dotfiles.** Place your `.gitconfig` in `~/.config/agent-sandbox/dotfiles/.gitconfig` on the host and enable the dotfiles volume mount. See [dotfiles.md](dotfiles.md) for setup details. Your gitconfig will be symlinked into `$HOME` at container startup and will layer on top of the container's system git defaults.

**Set git identity inside the container.** Run these commands before your first commit:

```bash
git config user.name "Your Name"
git config user.email "your@email.com"
```

This writes to the repo-level `.git/config`, which persists across container restarts (the workspace is a bind mount) and is not tracked by git.
