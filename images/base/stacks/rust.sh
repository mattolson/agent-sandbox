#!/bin/bash
# Install Rust via rustup with SHA256 verification
# Usage: rust.sh [toolchain]
#   toolchain: Rust toolchain (default: stable)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: rust.sh must be run as root" >&2
  exit 1
fi

TOOLCHAIN="${1:-stable}"

# Install build essentials needed for compiling
apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  pkg-config \
  libssl-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Detect target triple
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) TARGET="x86_64-unknown-linux-gnu" ;;
  arm64) TARGET="aarch64-unknown-linux-gnu" ;;
  *) echo "ERROR: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Download rustup-init and its SHA256 checksum
curl -fsSL "https://static.rust-lang.org/rustup/dist/${TARGET}/rustup-init" \
  -o "${TMPDIR}/rustup-init"
curl -fsSL "https://static.rust-lang.org/rustup/dist/${TARGET}/rustup-init.sha256" \
  -o "${TMPDIR}/rustup-init.sha256"

# The .sha256 file contains a path component; extract just the hash
EXPECTED_SHA256="$(awk '{print $1}' "${TMPDIR}/rustup-init.sha256")"
echo "${EXPECTED_SHA256}  ${TMPDIR}/rustup-init" | sha256sum -c -

chmod +x "${TMPDIR}/rustup-init"

# Install rustup and toolchain
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo

"${TMPDIR}/rustup-init" -y --default-toolchain "$TOOLCHAIN" --no-modify-path

# Make binaries accessible to all users
chmod -R a+r "$RUSTUP_HOME"
chmod -R a+rx "$CARGO_HOME/bin"

cat > /etc/zsh/zshenv.d/rust.zsh << 'ZSHENV'
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="/usr/local/cargo/bin:$PATH"
ZSHENV

cat > /etc/profile.d/rust.sh << 'PROFILE'
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH="/usr/local/cargo/bin:$PATH"
PROFILE

echo "Rust stack installed: $(/usr/local/cargo/bin/rustc --version)"
