# Git worktree path mismatch between host and container

## Problem

When multiple Claude Code instances create git worktrees inside the container, the worktree metadata stores absolute paths (e.g., `/workspace/.worktrees/feature-branch`). Git pushes happen on the host, where the repo is mounted at a different absolute path (e.g., `/Users/matt/projects/myrepo`). Git cannot resolve the worktree paths because the absolute paths don't match.

This makes it impossible to work with container-created worktrees from the host.

## Affected files

Git stores absolute paths in two places:
- `.git/worktrees/<name>/gitdir` - points to the worktree directory
- `<worktree>/.git` file - points back to `.git/worktrees/<name>/`

## Proposed solution

Git 2.48+ supports relative paths in worktree metadata via `worktree.useRelativePaths` config or the `--relative-paths` flag on `git worktree add`.

With relative paths, the pointer files resolve correctly regardless of where the repo root is mounted.

**Implementation:**
- Upgrade the base image's Git to 2.48+ (Debian bookworm's Git 2.39.5 cannot create relative worktree metadata)
- Set `worktree.useRelativePaths = true` in the container's git config
- Ensure worktrees are created under the repo root (e.g., `.worktrees/`) so they're visible through the bind mount
- Document the requirement that the host's git must be 2.48+ (macOS ships older Apple Git; Homebrew git is current)
- Container currently has git 2.39.5, so the fix is not a config-only change

## Scope

Small, self-contained base image change. Requires a Git upgrade, one config line, and documentation.

## Labels

enhancement, good first issue
