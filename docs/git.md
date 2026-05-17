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

### Credential setup (preferred): proxy-side injection

The recommended way to push to or read a private GitHub repo from inside the container is to let the proxy inject the credential at request time. No token is stored in the container.

1. Provision the secret on the host (one file per token, mode `0600`):

   ```bash
   mkdir -p "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
   chmod 700 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
   printf '%s' "ghp_examplevalue" \
     > "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.agent-sandbox.push-token"
   chmod 600 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.agent-sandbox.push-token"
   ```

   See [docs/secrets.md](secrets.md) for the directory layout, permission rules, and secret ID grammar.

2. Add a repo-scoped GitHub entry to your user policy (`agentbox edit policy`). For a readwrite push flow, use the `git-askpass` client shim so `git push` runs non-interactively:

   ```yaml
   services:
     - name: github
       merge_mode: replace
       repos:
         - owner/repo
       git:
         access: readwrite
         auth:
           secret: github.agent-sandbox.push-token
           client_shim:
             kind: git-askpass
   ```

   For read-only clone/fetch on a private repo, omit `client_shim` and use `access: read`. `client_shim` is only needed when an agent process pre-sets `Authorization` itself, which `git push` does and `git clone`/`git fetch` do not.

3. Apply the policy and open a new shell. The proxy reload picks up the new policy without restarting; the agent-side shim env exports (`GIT_ASKPASS`, `AGENTBOX_GIT_FAKE_USERNAME`, `AGENTBOX_GIT_FAKE_PASSWORD`, `GIT_TERMINAL_PROMPT`) are loaded by `/etc/agent-sandbox/shell-init.sh`, so already-running shells will not see them until they restart.

   ```bash
   agentbox proxy reload
   # then open a new shell (e.g. `agentbox exec`) inside the container
   ```

Focused policy examples under `docs/policy/examples/`:

- [github-private-git.yaml](policy/examples/github-private-git.yaml) — read-only clone/fetch.
- [github-git-push.yaml](policy/examples/github-git-push.yaml) — readwrite with the askpass shim.

See [docs/policy/schema.md](policy/schema.md) for the full authored shape, including non-GitHub services via `domains[].transform.request`.

### Credential setup (last resort): credential-store with a PAT

**Prefer proxy-side injection.** Reach for this only when the catalog cannot cover the host (a non-GitHub service with no `domains[].transform.request` entry, an offline test, etc.). For private GitHub git operations, use the proxy-injection path above — not this.

Trade-offs you are accepting:

- The credential lives in plaintext at `~/.git-credentials` inside the container.
- The file persists in the agent's Docker volume across image bumps. Clearing it requires `agentbox destroy`.
- A leaked token is as broad as its scope. The proxy cannot constrain a request once the agent is the one sending the credential.

Create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to the minimum necessary repositories, then:

```bash
git config --global credential.helper store
```

On the next authenticated `git` operation, git prompts for username and token. The credential is saved to `~/.git-credentials` and reused from then on. See the [security section](../README.md#git-credentials) for ways to limit exposure.

#### Don't set `credential.helper = store` globally

The proxy-injection path doesn't need a credential helper. Drop `credential.helper = store` from any gitconfig you mount via dotfiles — leaving it set risks writing plaintext credentials to `~/.git-credentials` on any flow that bypasses the askpass shim.

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
