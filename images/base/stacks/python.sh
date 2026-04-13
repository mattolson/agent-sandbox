#!/bin/bash
# Install a Python 3 development environment from apt
# Usage: python.sh [version]
#   version: not used (apt provides system Python), accepted for interface consistency
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: python.sh must be run as root" >&2
  exit 1
fi

apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  libffi-dev \
  libssl-dev \
  pipx \
  pkg-config \
  python3 \
  python3-dev \
  python3-pip \
  python3-setuptools \
  python3-venv \
  python3-wheel \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Convenience symlinks
ln -sf /usr/bin/python3 /usr/local/bin/python
ln -sf /usr/bin/pip3 /usr/local/bin/pip

# Python tooling and caches live under the dev user's home directory.
mkdir -p \
  /home/dev/.cache/pip \
  /home/dev/.config/pip \
  /home/dev/.local/pipx/bin \
  /home/dev/.local/bin
chown -R dev:dev /home/dev/.cache /home/dev/.config/pip /home/dev/.local

# PATH entry for Python-managed tools plus shared cache/tooling defaults.
# Keep agent binaries in ~/.local/bin ahead of pipx-installed tools so a
# user-installed CLI cannot accidentally shadow the active agent binary.
cat > /etc/zsh/zshenv.d/python.zsh << 'ZSHENV'
export PATH="$HOME/.local/bin:$HOME/.local/pipx/bin:/usr/local/bin:$PATH"
export PIP_CACHE_DIR="$HOME/.cache/pip"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIPX_HOME="$HOME/.local/pipx"
export PIPX_BIN_DIR="$HOME/.local/pipx/bin"
ZSHENV

cat > /etc/profile.d/python.sh << 'PROFILE'
export PATH="$HOME/.local/bin:$HOME/.local/pipx/bin:/usr/local/bin:$PATH"
export PIP_CACHE_DIR="$HOME/.cache/pip"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIPX_HOME="$HOME/.local/pipx"
export PIPX_BIN_DIR="$HOME/.local/pipx/bin"
PROFILE

echo "Python stack installed: $(python3 --version)"
