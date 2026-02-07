#!/bin/bash
set -euo pipefail

# Build agent-sandbox images locally
#
# Usage: ./build.sh [base|proxy|claude|copilot|all] [docker build options...]
#
# Environment variables (all optional):
#   TZ                      - Timezone (default: America/Los_Angeles)
#   CLAUDE_CODE_VERSION     - Claude Code version (default: latest)
#   COPILOT_VERSION         - GitHub Copilot CLI version (default: latest)
#   EXTRA_PACKAGES          - Additional apt packages for the base image
#   CLAUDE_EXTRA_PACKAGES   - Additional apt packages for the claude image
#   COPILOT_EXTRA_PACKAGES  - Additional apt packages for the copilot image
#   PROXY_EXTRA_PACKAGES    - Additional apt packages for the proxy image
#
# Examples:
#   CLAUDE_CODE_VERSION=1.0.0 ./build.sh claude
#   EXTRA_PACKAGES="jq gh" ./build.sh base
#   ./build.sh --no-cache              # builds all with --no-cache
#   ./build.sh base --no-cache --progress=plain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse target and extra args
# If first arg is a known target, use it; otherwise default to 'all'
case "${1:-}" in
  base|claude|proxy|copilot|all)
    TARGET="$1"
    shift
    ;;
  *)
    TARGET="all"
    ;;
esac
DOCKER_BUILD_ARGS=("$@")

# Defaults
: "${TZ:=America/Los_Angeles}"
: "${CLAUDE_CODE_VERSION:=latest}"
: "${COPILOT_VERSION:=latest}"
: "${EXTRA_PACKAGES:=}"
: "${CLAUDE_EXTRA_PACKAGES:=}"
: "${COPILOT_EXTRA_PACKAGES:=}"
: "${PROXY_EXTRA_PACKAGES:=}"

build_base() {
  echo "Building agent-sandbox-base..."
  echo "  TZ=$TZ"
  [ -n "$EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$EXTRA_PACKAGES"
  docker build \
    --build-arg TZ="$TZ" \
    --build-arg EXTRA_PACKAGES="$EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-base:local \
    "$SCRIPT_DIR/base"
}

build_proxy() {
  echo "Building agent-sandbox-proxy..."
  [ -n "$PROXY_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$PROXY_EXTRA_PACKAGES"
  docker build \
    --build-arg EXTRA_PACKAGES="$PROXY_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-proxy:local \
    "$SCRIPT_DIR/proxy"
}

build_claude() {
  echo "Building agent-sandbox-claude..."
  echo "  CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION"
  [ -n "$CLAUDE_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$CLAUDE_EXTRA_PACKAGES"
  docker build \
    --build-arg BASE_IMAGE=agent-sandbox-base:local \
    --build-arg CLAUDE_CODE_VERSION="$CLAUDE_CODE_VERSION" \
    --build-arg EXTRA_PACKAGES="$CLAUDE_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-claude:local \
    "$SCRIPT_DIR/agents/claude"
}

build_copilot() {
  echo "Building agent-sandbox-copilot..."
  echo "  COPILOT_VERSION=$COPILOT_VERSION"
  [ -n "$COPILOT_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$COPILOT_EXTRA_PACKAGES"
  docker build \
    --build-arg BASE_IMAGE=agent-sandbox-base:local \
    --build-arg COPILOT_VERSION="$COPILOT_VERSION" \
    --build-arg EXTRA_PACKAGES="$COPILOT_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-copilot:local \
    "$SCRIPT_DIR/agents/copilot"
}

case "$TARGET" in
  base)
    build_base
    ;;
  proxy)
    build_proxy
    ;;
  claude)
    build_claude
    ;;
  copilot)
    build_copilot
    ;;
  all)
    build_base
    build_proxy
    build_claude
    build_copilot
    ;;
  *)
    echo "Usage: $0 [base|proxy|claude|copilot|all] [docker build options...]"
    echo ""
    echo "Any additional arguments are passed to docker build."
    echo ""
    echo "Environment variables:"
    echo "  TZ                      Timezone (default: America/Los_Angeles)"
    echo "  CLAUDE_CODE_VERSION     Claude Code version (default: latest)"
    echo "  COPILOT_VERSION         GitHub Copilot CLI version (default: latest)"
    echo "  EXTRA_PACKAGES          Additional apt packages for base image"
    echo "  CLAUDE_EXTRA_PACKAGES   Additional apt packages for claude image"
    echo "  COPILOT_EXTRA_PACKAGES  Additional apt packages for copilot image"
    echo "  PROXY_EXTRA_PACKAGES    Additional apt packages for proxy image"
    exit 1
    ;;
esac

echo "Done."
