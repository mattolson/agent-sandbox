# Agent Sandbox shell initialization
# Sourced at the end of .zshrc

# Source agent-specific aliases if present
[ -f /etc/agent-sandbox/aliases.sh ] && source /etc/agent-sandbox/aliases.sh

# Source user customizations from shell.d
# Mount your scripts to ~/.config/agent-sandbox/shell.d/
if [ -d ~/.config/agent-sandbox/shell.d ]; then
  for f in ~/.config/agent-sandbox/shell.d/*.sh(N); do
    [ -f "$f" ] && source "$f"
  done
fi
