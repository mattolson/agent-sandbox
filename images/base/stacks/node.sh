#!/bin/bash
# Install Node.js via NodeSource apt repository with GPG verification
# Usage: node.sh [major_version]
#   major_version: Node.js major version (default: 22)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: node.sh must be run as root" >&2
  exit 1
fi

NODE_MAJOR="${1:-22}"

# Set up NodeSource apt repository with GPG key verification
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.key
gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.key
rm /tmp/nodesource.key

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list

apt-get update && apt-get install -y nodejs
apt-get clean && rm -rf /var/lib/apt/lists/*

# npm global prefix for dev user (avoid permission issues with global installs)
mkdir -p /home/dev/.npm-global
chown dev:dev /home/dev/.npm-global

cat > /etc/zsh/zshenv.d/node.zsh << 'ZSHENV'
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
ZSHENV

cat > /etc/profile.d/node.sh << 'PROFILE'
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
PROFILE

echo "Node.js stack installed: $(node --version)"
