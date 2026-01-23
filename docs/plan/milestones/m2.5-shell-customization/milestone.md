# m2.5-shell-customization

Allow users to customize their shell environment without modifying the base image.

## Goals

- Extract built-in aliases from Dockerfile to a sourceable file
- Add hook directory for user shell customizations
- Support mounting dotfiles directory for complex setups
- Document customization patterns

## Current State

Built-in aliases are hardcoded in `images/agents/claude/Dockerfile`:

```dockerfile
RUN echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> ~/.zshrc && \
  echo "alias yc='yolo-claude'" >> ~/.zshrc
```

Problems:
- Not all users want these aliases
- No clean way to add user customizations
- Users who want their host shell setup can't easily bring it in

## Design

### Shell initialization order

1. Base zsh config (oh-my-zsh, theme, etc.)
2. Built-in agent aliases (`/etc/agent-sandbox/aliases.sh`) - optional, sourced by default
3. User customizations (`~/.config/agent-sandbox/shell.d/*.sh`) - if mounted

### Built-in aliases

Move from hardcoded in Dockerfile to a separate file:

```
/etc/agent-sandbox/aliases.sh
```

Contents:
```bash
# Agent Sandbox convenience aliases
alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'
alias yc='yolo-claude'
```

Sourced at end of `.zshrc`:
```bash
# Source agent-sandbox aliases
[ -f /etc/agent-sandbox/aliases.sh ] && source /etc/agent-sandbox/aliases.sh
```

### User customization hook

Add to `.zshrc`:
```bash
# Source user customizations
if [ -d ~/.config/agent-sandbox/shell.d ]; then
  for f in ~/.config/agent-sandbox/shell.d/*.sh; do
    [ -f "$f" ] && source "$f"
  done
fi
```

User mounts their customizations:
```yaml
# docker-compose.yml or devcontainer.json
volumes:
  - ${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro
```

### Dotfiles directory

For users with existing dotfiles repos, mount the whole thing:

```yaml
volumes:
  - ${HOME}/.dotfiles:/home/dev/.dotfiles:ro
```

Then create a script in `shell.d/` that symlinks as needed:

```bash
# ~/.config/agent-sandbox/shell.d/00-dotfiles.sh
[ -d ~/.dotfiles ] && {
  ln -sf ~/.dotfiles/aliases ~/.aliases
  ln -sf ~/.dotfiles/functions ~/.functions
  source ~/.aliases
  source ~/.functions
}
```

## Tasks

### m2.5.1 - Extract aliases to file

- Create `/etc/agent-sandbox/aliases.sh` in base image
- Remove hardcoded aliases from claude Dockerfile
- Update `.zshrc` to source the aliases file

### m2.5.2 - Add shell.d hook

- Update `.zshrc` to source `~/.config/agent-sandbox/shell.d/*.sh`
- Create the directory structure in image (empty, for mount target)

### m2.5.3 - Update template

- Add commented-out mounts for shell.d and dotfiles to template
- Document customization in template README

### m2.5.4 - Documentation

- Add examples for common customizations
- Document how to skip built-in aliases if unwanted
- Document dotfiles symlink pattern

## Definition of Done

- [x] Built-in aliases in separate sourceable file
- [x] shell.d hook directory sourced by zshrc
- [x] Template shows example mounts (commented out)
- [x] README documents customization patterns
- [ ] Tested: custom aliases work
- [ ] Tested: dotfiles symlink pattern works

## Examples

### Simple: Add a few aliases

```bash
# ~/.config/agent-sandbox/shell.d/my-aliases.sh
alias ll='ls -la'
alias gs='git status'
```

### Medium: Override built-in aliases

```bash
# ~/.config/agent-sandbox/shell.d/99-overrides.sh
# Use different flags for yolo-claude
alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions --verbose'
```

### Advanced: Full dotfiles setup

```bash
# ~/.config/agent-sandbox/shell.d/00-dotfiles.sh
if [ -d ~/.dotfiles ]; then
  # Symlink specific files
  ln -sf ~/.dotfiles/zsh/aliases.zsh ~/.aliases
  ln -sf ~/.dotfiles/zsh/functions.zsh ~/.functions
  ln -sf ~/.dotfiles/git/gitconfig ~/.gitconfig

  # Source shell files
  source ~/.aliases
  source ~/.functions
fi
```

### Skip built-in aliases entirely

```bash
# ~/.config/agent-sandbox/shell.d/00-no-builtins.sh
# Unset the built-in aliases if you don't want them
unalias yolo-claude 2>/dev/null
unalias yc 2>/dev/null
```
