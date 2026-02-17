#!/bin/bash
set -euo pipefail

# Build agent-sandbox images locally
#
# Usage: ./build.sh [base|proxy|claude|copilot|cli|all] [docker build options...]
#
# Environment variables (all optional):
#   TZ                      - Timezone (default: America/Los_Angeles)
#   CLAUDE_CODE_VERSION     - Claude Code version (default: latest)
#   COPILOT_VERSION         - GitHub Copilot CLI version (default: latest)
#   EXTRA_PACKAGES          - Additional apt packages for the base image
#   CLAUDE_EXTRA_PACKAGES   - Additional apt packages for the claude image
#   COPILOT_EXTRA_PACKAGES  - Additional apt packages for the copilot image
#   PROXY_EXTRA_PACKAGES    - Additional apt packages for the proxy image
#   STACKS                  - Comma-separated language stacks for the base image (e.g. "python,go:1.23")
#   TAG                     - Image tag (default: local)
#
# Examples:
#   CLAUDE_CODE_VERSION=1.0.0 ./build.sh claude
#   EXTRA_PACKAGES="jq gh" ./build.sh base
#   STACKS="python,go:1.23" ./build.sh base
#   TAG=python-go STACKS="python,go" ./build.sh all
#   ./build.sh --no-cache              # builds all with --no-cache
#   ./build.sh base --no-cache --progress=plain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse target and extra args
# If first arg is a known target, use it; otherwise default to 'all'
case "${1:-}" in
  base|claude|proxy|copilot|cli|all)
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
: "${STACKS:=}"
: "${TAG:=local}"

build_base() {
  echo "Building agent-sandbox-base..."
  echo "  TZ=$TZ"
  [ -n "$EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$EXTRA_PACKAGES"
  [ -n "$STACKS" ] && echo "  STACKS=$STACKS"
  [ "$TAG" != "local" ] && echo "  TAG=$TAG"
  docker build \
    --build-arg TZ="$TZ" \
    --build-arg EXTRA_PACKAGES="$EXTRA_PACKAGES" \
    --build-arg STACKS="$STACKS" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-base:$TAG \
    "$SCRIPT_DIR/base"
}

build_proxy() {
  echo "Building agent-sandbox-proxy..."
  [ -n "$PROXY_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$PROXY_EXTRA_PACKAGES"
  [ "$TAG" != "local" ] && echo "  TAG=$TAG"
  docker build \
    --build-arg EXTRA_PACKAGES="$PROXY_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-proxy:$TAG \
    "$SCRIPT_DIR/proxy"
}

build_claude() {
  echo "Building agent-sandbox-claude..."
  echo "  CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION"
  [ -n "$CLAUDE_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$CLAUDE_EXTRA_PACKAGES"
  [ "$TAG" != "local" ] && echo "  TAG=$TAG"
  docker build \
    --build-arg BASE_IMAGE=agent-sandbox-base:$TAG \
    --build-arg CLAUDE_CODE_VERSION="$CLAUDE_CODE_VERSION" \
    --build-arg EXTRA_PACKAGES="$CLAUDE_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-claude:$TAG \
    "$SCRIPT_DIR/agents/claude"
}

build_copilot() {
  echo "Building agent-sandbox-copilot..."
  echo "  COPILOT_VERSION=$COPILOT_VERSION"
  [ -n "$COPILOT_EXTRA_PACKAGES" ] && echo "  EXTRA_PACKAGES=$COPILOT_EXTRA_PACKAGES"
  [ "$TAG" != "local" ] && echo "  TAG=$TAG"
  docker build \
    --build-arg BASE_IMAGE=agent-sandbox-base:$TAG \
    --build-arg COPILOT_VERSION="$COPILOT_VERSION" \
    --build-arg EXTRA_PACKAGES="$COPILOT_EXTRA_PACKAGES" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-copilot:$TAG \
    "$SCRIPT_DIR/agents/copilot"
}

build_cli() {
  echo "Building agent-sandbox-cli..."
  [ "$TAG" != "local" ] && echo "  TAG=$TAG"
  docker build \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -f "$SCRIPT_DIR/cli/Dockerfile" \
    -t agent-sandbox-cli:$TAG \
    "$SCRIPT_DIR/.."
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
  cli)
    build_cli
    ;;
  all)
    build_base
    build_proxy
    build_claude
    build_copilot
    build_cli
    ;;
  *)
    echo "Usage: $0 [base|proxy|claude|copilot|cli|all] [docker build options...]"
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
    echo "  STACKS                  Language stacks for base image, comma-separated (e.g. python,go:1.23)"
    echo "  TAG                     Image tag (default: local)"
    exit 1
    ;;
esac

echo "Done."
