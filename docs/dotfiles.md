# Dotfiles and Shell Customization

## Dotfiles Support

You can optionally mount your dotfiles directory and have them auto-linked into `$HOME` at container startup:

```yaml
volumes:
  - ${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro
```

The entrypoint recursively walks `/home/dev/.dotfiles` and creates symlinks for each file at the corresponding `$HOME` path. Intermediate directories are created as needed.

For example, if your dotfiles contain:
```
.dotfiles/
  .zshrc
  .gitconfig
  .claude/
    CLAUDE.md
    settings.json
  .config/
    git/config
    starship.toml
```

The container will have:
- `~/.zshrc` -> `~/.dotfiles/.zshrc`
- `~/.gitconfig` -> `~/.dotfiles/.gitconfig`
- `~/.claude/CLAUDE.md` -> `~/.dotfiles/.claude/CLAUDE.md`
- `~/.claude/settings.json` -> `~/.dotfiles/.claude/settings.json`
- `~/.config/git/config` -> `~/.dotfiles/.config/git/config`
- `~/.config/starship.toml` -> `~/.dotfiles/.config/starship.toml`

Docker bind mounts (like individually mounted `CLAUDE.md`) take precedence over dotfile symlinks.

## Shell Customization

You can also optionally mount scripts from `~/.config/agent-sandbox/shell.d/` to customize your shell environment. Any `*.sh` files are sourced when zsh starts.

```bash
mkdir -p ~/.config/agent-sandbox/shell.d

cat > ~/.config/agent-sandbox/shell.d/my-aliases.sh << 'EOF'
alias ll='ls -la'
alias gs='git status'
EOF
```

The `agentbox init` command prompts whether to enable shell customizations when setting up your project and will set up the volume mount.

shell.d scripts are sourced from the system-level zshrc (`/etc/zsh/zshrc`), which runs before `~/.zshrc`. This means your dotfiles can include a custom `.zshrc` without breaking this integration.
