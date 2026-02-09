#!/bin/bash
# Install Rust via rustup with system-wide install
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

# Install rustup and toolchain as dev user
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo

curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain "$TOOLCHAIN" --no-modify-path

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
