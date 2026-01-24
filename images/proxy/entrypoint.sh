#!/bin/bash
set -e

# mitmproxy generates its CA on first run at ~/.mitmproxy/
# We need to export just the certificate (not the private key) for clients

CA_DIR="/home/mitmproxy/.mitmproxy"
EXPORT_DIR="/ca-export"

# Generate the CA if it doesn't exist yet
if [ ! -f "$CA_DIR/mitmproxy-ca-cert.pem" ]; then
  # Run mitmdump briefly to trigger CA generation
  timeout 2 mitmdump --set confdir="$CA_DIR" || true
fi

# Copy only the public certificate to the export volume
if [ -f "$CA_DIR/mitmproxy-ca-cert.pem" ] && [ -d "$EXPORT_DIR" ]; then
  cp "$CA_DIR/mitmproxy-ca-cert.pem" "$EXPORT_DIR/ca.crt"
fi

# Run mitmdump with all passed arguments, using the same confdir
exec mitmdump --set confdir="$CA_DIR" "$@"
