#!/bin/bash
# Install mitmproxy CA certificate into system trust store
set -e

MITMPROXY_CA="/etc/mitmproxy/ca.crt"
DEST="/usr/local/share/ca-certificates/mitmproxy-ca.crt"

if [ ! -f "$MITMPROXY_CA" ]; then
  echo "Error: mitmproxy CA certificate not found at $MITMPROXY_CA"
  exit 1
fi

cp "$MITMPROXY_CA" "$DEST"
update-ca-certificates --fresh > /dev/null 2>&1
echo "mitmproxy CA certificate installed successfully"
