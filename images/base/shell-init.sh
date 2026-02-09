# Agent Sandbox shell initialization
# Sourced from /etc/zsh/zshrc (system-level, runs before ~/.zshrc)

# Source user customizations from shell.d
# Mount your scripts to ~/.config/agent-sandbox/shell.d/
if [ -d ~/.config/agent-sandbox/shell.d ]; then
  for f in ~/.config/agent-sandbox/shell.d/*.sh(N); do
    [ -f "$f" ] && source "$f"
  done
fi
