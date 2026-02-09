#!/bin/bash
# Install Go from official tarball
# Usage: go.sh [version]
#   version: Go version without 'go' prefix (default: 1.23.6)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: go.sh must be run as root" >&2
  exit 1
fi

GO_VERSION="${1:-1.23.6}"

# Detect architecture
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) GOARCH="amd64" ;;
  arm64) GOARCH="arm64" ;;
  *) echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" | tar -C /usr/local -xz

# GOPATH for dev user
mkdir -p /home/dev/go
chown dev:dev /home/dev/go

cat > /etc/zsh/zshenv.d/go.zsh << 'ZSHENV'
export GOPATH="$HOME/go"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
ZSHENV

cat > /etc/profile.d/go.sh << 'PROFILE'
export GOPATH="$HOME/go"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
PROFILE

echo "Go stack installed: $(/usr/local/go/bin/go version)"
