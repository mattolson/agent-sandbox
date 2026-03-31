#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_FILE="${METADATA_FILE:-$SCRIPT_DIR/.agent-sandbox/active-target.env}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-$SCRIPT_DIR/Dockerfile.dev}"
BUILD_CONTEXT="${BUILD_CONTEXT:-$SCRIPT_DIR}"

usage() {
	cat <<'EOF'
Usage: ./build-dev-image.sh [docker build options...]

Builds the local development image from Dockerfile.dev for the active agent.

Optional environment variables:
  AGENT            Agent name to build for (default: ACTIVE_AGENT from .agent-sandbox)
  IMAGE_TAG        Docker tag to publish (default: agent-sandbox-dev:<agent>)
  METADATA_FILE    Agent metadata file (default: ./.agent-sandbox/active-target.env)
  DOCKERFILE_PATH  Dockerfile to build (default: ./Dockerfile.dev)
  BUILD_CONTEXT    Docker build context (default: repo root)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
	printf 'docker is required to build the local dev image\n' >&2
	exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
	printf 'Dockerfile not found: %s\n' "$DOCKERFILE_PATH" >&2
	exit 1
fi

ACTIVE_AGENT=""
if [ -f "$METADATA_FILE" ]; then
	# shellcheck disable=SC1090
	. "$METADATA_FILE"
	ACTIVE_AGENT="${ACTIVE_AGENT:-}"
fi

AGENT="${AGENT:-$ACTIVE_AGENT}"
if [ -z "$AGENT" ]; then
	printf 'Unable to determine agent. Set AGENT or provide %s\n' "$METADATA_FILE" >&2
	exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-agent-sandbox-dev:$AGENT}"
OVERRIDE_FILE="$SCRIPT_DIR/.agent-sandbox/compose/user.agent.$AGENT.override.yml"

printf 'Building %s from %s\n' "$IMAGE_TAG" "$DOCKERFILE_PATH"
printf 'Active agent: %s\n' "$AGENT"
docker build \
	--build-arg AGENT="$AGENT" \
	-f "$DOCKERFILE_PATH" \
	-t "$IMAGE_TAG" \
	"$@" \
	"$BUILD_CONTEXT"

printf '\nBuilt %s\n' "$IMAGE_TAG"
if [ -f "$OVERRIDE_FILE" ] && grep -Eq "^[[:space:]]*image:[[:space:]]*$IMAGE_TAG[[:space:]]*$" "$OVERRIDE_FILE"; then
	printf 'The local %s override already points at this tag.\n' "$AGENT"
elif [ -f "$OVERRIDE_FILE" ]; then
	printf 'If you want agentbox to use it, set image: %s in %s\n' "$IMAGE_TAG" "$OVERRIDE_FILE"
fi
printf 'Next step: agentbox up -d\n'
