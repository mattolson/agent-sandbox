#!/bin/bash
# Configure apt to use a proxy
# Usage: configure-apt-proxy.sh <proxy_url>

set -e

PROXY_URL="$1"
APT_PROXY_CONF="/etc/apt/apt.conf.d/99proxy"

if [ -z "$PROXY_URL" ]; then
  echo "Usage: configure-apt-proxy.sh <proxy_url>"
  exit 1
fi

# Validate proxy URL format - block quotes/semicolons to prevent apt config injection
if ! echo "$PROXY_URL" | grep -qE '^https?://[^";[:space:]]+$'; then
  echo "Error: Invalid proxy URL format"
  exit 1
fi

cat > "$APT_PROXY_CONF" <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF

echo "Configured apt proxy: $PROXY_URL"
