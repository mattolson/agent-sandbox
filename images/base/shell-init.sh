# Agent Sandbox shell initialization
# Sourced from /etc/zsh/zshrc (system-level, runs before ~/.zshrc)

# Node.js ignores the system trust store and bundles its own CAs.
# Tell it to also trust the proxy CA so HTTPS works through mitmproxy.
if [ -f /etc/mitmproxy/ca.crt ]; then
  export NODE_EXTRA_CA_CERTS=/etc/mitmproxy/ca.crt
fi

# Source generated fake credential-shim initialization when the proxy configured one.
CREDENTIAL_SHIM_INIT="${AGENTBOX_CREDENTIAL_SHIM_INIT_PATH:-/run/agentbox/credential-shims/init.zsh}"
if [ -f "$CREDENTIAL_SHIM_INIT" ]; then
  source "$CREDENTIAL_SHIM_INIT"
fi

# Source user customizations from shell.d
# Mount your scripts to ~/.config/agent-sandbox/shell.d/
if [ -d ~/.config/agent-sandbox/shell.d ]; then
  for f in ~/.config/agent-sandbox/shell.d/*.sh(N); do
    [ -f "$f" ] && source "$f"
  done
fi
