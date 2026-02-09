#!/bin/bash
# Install Go from official tarball with SHA256 verification
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

TARBALL="go${GO_VERSION}.linux-${GOARCH}.tar.gz"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Download tarball
curl -fsSL "https://go.dev/dl/${TARBALL}" -o "${TMPDIR}/${TARBALL}"

# Fetch expected SHA256 from Go's JSON API and verify
EXPECTED_SHA256="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' \
  | jq -r --arg ver "go${GO_VERSION}" --arg arch "$GOARCH" \
    '.[] | select(.version==$ver) | .files[] | select(.os=="linux" and .arch==$arch) | .sha256')"

if [ -z "$EXPECTED_SHA256" ]; then
  echo "ERROR: Could not find SHA256 for go${GO_VERSION} linux/${GOARCH}" >&2
  exit 1
fi

echo "${EXPECTED_SHA256}  ${TMPDIR}/${TARBALL}" | sha256sum -c -

tar -C /usr/local -xzf "${TMPDIR}/${TARBALL}"

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
