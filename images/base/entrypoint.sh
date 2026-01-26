#!/bin/bash
set -e

# Initialize firewall if not already done
# Check if OUTPUT policy is already DROP (set by init-firewall.sh)
if iptables -S OUTPUT 2>/dev/null | grep -q "^-P OUTPUT DROP"; then
  echo "Firewall already initialized."
else
  echo "Initializing firewall..."
  if ! sudo /usr/local/bin/init-firewall.sh; then
    echo ""
    echo "=========================================="
    echo "FATAL: Firewall initialization failed!"
    echo "Container cannot start without working firewall."
    echo "Check the errors above and rebuild the image."
    echo "=========================================="
    exit 1
  fi
fi

# Install mitmproxy CA certificate if available - this is used by the sidecar
# proxy to properly handle TLS requests
MITMPROXY_CA="/etc/mitmproxy/ca.crt"
if [ -f "$MITMPROXY_CA" ]; then
  # Check if already installed by comparing with installed cert
  INSTALLED_CA="/usr/local/share/ca-certificates/mitmproxy-ca.crt"
  if [ ! -f "$INSTALLED_CA" ] || ! cmp -s "$MITMPROXY_CA" "$INSTALLED_CA"; then
    echo "Installing mitmproxy CA certificate..."
    sudo /usr/local/bin/install-proxy-ca.sh
  fi
fi

# Configure apt to use proxy if HTTP_PROXY is set
# sudo strips env vars due to env_reset, so apt needs its own config
if [ -n "$HTTP_PROXY" ]; then
  APT_PROXY_CONF="/etc/apt/apt.conf.d/99proxy"
  if [ ! -f "$APT_PROXY_CONF" ]; then
    sudo /usr/local/bin/configure-apt-proxy.sh "${HTTPS_PROXY:-$HTTP_PROXY}"
  fi
fi

# Execute the provided command (or default to zsh)
exec "${@:-zsh}"
