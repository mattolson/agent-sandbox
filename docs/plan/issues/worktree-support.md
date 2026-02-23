# Git worktree path mismatch between host and container

## Problem

When multiple Claude Code instances create git worktrees inside the container, the worktree metadata stores absolute paths (e.g., `/workspace/.worktrees/feature-branch`). Git pushes happen on the host, where the repo is mounted at a different absolute path (e.g., `/Users/matt/projects/myrepo`). Git cannot resolve the worktree paths because the absolute paths don't match.

This makes it impossible to work with container-created worktrees from the host.

## Affected files

Git stores absolute paths in two places:
- `.git/worktrees/<name>/gitdir` - points to the worktree directory
- `<worktree>/.git` file - points back to `.git/worktrees/<name>/`

## Proposed solution

Git 2.38+ supports relative paths in worktree metadata via `worktree.useRelativePaths` config or the `--relative-paths` flag on `git worktree add`.

With relative paths, the pointer files resolve correctly regardless of where the repo root is mounted.

**Implementation:**
- Set `worktree.useRelativePaths = true` in the container's git config (via base image or shell-init)
- Ensure worktrees are created under the repo root (e.g., `.worktrees/`) so they're visible through the bind mount
- Document the requirement that the host's git must be 2.38+ (macOS ships older Apple Git; Homebrew git is current)
- Container already has git 2.39.5, which supports this feature

## Scope

Small, self-contained change. Likely a single config line in the base image or shell-init, plus documentation.

## Labels

enhancement, good first issue
