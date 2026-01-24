#!/bin/bash
set -e

# Initialize firewall if not already done
# Check if allowed-domains ipset exists (created by init-firewall.sh)
if ! ipset list allowed-domains >/dev/null 2>&1; then
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
else
  echo "Firewall already initialized."
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

# Execute the provided command (or default to zsh)
exec "${@:-zsh}"
