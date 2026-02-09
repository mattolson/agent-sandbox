#!/bin/bash
# Install Python 3 + pip + venv from apt
# Usage: python.sh [version]
#   version: not used (apt provides system Python), accepted for interface consistency
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: python.sh must be run as root" >&2
  exit 1
fi

apt-get update && apt-get install -y --no-install-recommends \
  python3 \
  python3-pip \
  python3-venv \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Convenience symlinks
ln -sf /usr/bin/python3 /usr/local/bin/python

# PATH entry (python3 is already in /usr/bin, but pip may install to /usr/local/bin)
cat > /etc/zsh/zshenv.d/python.zsh << 'ZSHENV'
export PATH="/usr/local/bin:$PATH"
ZSHENV

cat > /etc/profile.d/python.sh << 'PROFILE'
export PATH="/usr/local/bin:$PATH"
PROFILE

echo "Python stack installed: $(python3 --version)"
