#!/bin/bash
set -e

# Initialize firewall if not already done
# Check if allowed-domains ipset exists (created by init-firewall.py)
if ! ipset list allowed-domains >/dev/null 2>&1; then
  echo "Initializing firewall..."
  if ! sudo /usr/local/bin/init-firewall.py; then
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

# Execute the provided command (or default to zsh)
exec "${@:-zsh}"
