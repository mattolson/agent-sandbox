#!/bin/bash
set -euo pipefail

# Build agent-sandbox images locally
#
# Usage: ./build.sh [base|claude|proxy|all] [docker build options...]
#
# Environment variables (all optional):
#   TZ                    - Timezone (default: America/Los_Angeles)
#   YQ_VERSION            - yq version (default: v4.44.1)
#   GIT_DELTA_VERSION     - git-delta version (default: 0.18.2)
#   ZSH_IN_DOCKER_VERSION - zsh-in-docker version (default: 1.2.0)
#   CLAUDE_CODE_VERSION   - Claude Code version (default: latest)
#
# Examples:
#   CLAUDE_CODE_VERSION=1.0.0 ./build.sh claude
#   ./build.sh --no-cache              # builds all with --no-cache
#   ./build.sh base --no-cache --progress=plain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse target and extra args
# If first arg is a known target, use it; otherwise default to 'all'
case "${1:-}" in
  base|claude|proxy|all)
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
: "${YQ_VERSION:=v4.44.1}"
: "${GIT_DELTA_VERSION:=0.18.2}"
: "${ZSH_IN_DOCKER_VERSION:=1.2.0}"
: "${CLAUDE_CODE_VERSION:=latest}"

build_base() {
  echo "Building agent-sandbox-base..."
  echo "  TZ=$TZ"
  echo "  YQ_VERSION=$YQ_VERSION"
  echo "  GIT_DELTA_VERSION=$GIT_DELTA_VERSION"
  echo "  ZSH_IN_DOCKER_VERSION=$ZSH_IN_DOCKER_VERSION"
  docker build \
    --build-arg TZ="$TZ" \
    --build-arg YQ_VERSION="$YQ_VERSION" \
    --build-arg GIT_DELTA_VERSION="$GIT_DELTA_VERSION" \
    --build-arg ZSH_IN_DOCKER_VERSION="$ZSH_IN_DOCKER_VERSION" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-base:local \
    "$SCRIPT_DIR/base"
}

build_claude() {
  echo "Building agent-sandbox-claude..."
  echo "  CLAUDE_CODE_VERSION=$CLAUDE_CODE_VERSION"
  docker build \
    --build-arg BASE_IMAGE=agent-sandbox-base:local \
    --build-arg CLAUDE_CODE_VERSION="$CLAUDE_CODE_VERSION" \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-claude:local \
    "$SCRIPT_DIR/agents/claude"
}

build_proxy() {
  echo "Building agent-sandbox-proxy..."
  docker build \
    ${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"} \
    -t agent-sandbox-proxy:local \
    "$SCRIPT_DIR/proxy"
}

case "$TARGET" in
  base)
    build_base
    ;;
  claude)
    build_claude
    ;;
  proxy)
    build_proxy
    ;;
  all)
    build_base
    build_claude
    build_proxy
    ;;
  *)
    echo "Usage: $0 [base|claude|proxy|all] [docker build options...]"
    echo ""
    echo "Any additional arguments are passed to docker build."
    echo ""
    echo "Environment variables:"
    echo "  TZ                    Timezone (default: America/Los_Angeles)"
    echo "  YQ_VERSION            yq version (default: v4.44.1)"
    echo "  GIT_DELTA_VERSION     git-delta version (default: 0.18.2)"
    echo "  ZSH_IN_DOCKER_VERSION zsh-in-docker version (default: 1.2.0)"
    echo "  CLAUDE_CODE_VERSION   Claude Code version (default: latest)"
    exit 1
    ;;
esac

echo "Done."
