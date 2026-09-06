#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
METADATA_FILE="${METADATA_FILE:-$REPO_ROOT/.agent-sandbox/active-target.env}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-$REPO_ROOT/Dockerfile.dev}"
BUILD_CONTEXT="${BUILD_CONTEXT:-$REPO_ROOT}"
IMAGE_BUILDER="${IMAGE_BUILDER:-$REPO_ROOT/images/build.sh}"
VERSIONS_FILE="${VERSIONS_FILE:-$SCRIPT_DIR/dev-image-versions.env}"

is_supported_agent() {
	case "$1" in
		claude|copilot|codex|gemini|factory|opencode|pi|hermes)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

usage() {
	cat <<'EOF'
Usage: ./scripts/build-dev-image.bash [docker build options...]

Builds the local development image from Dockerfile.dev for the active agent.
Before building Dockerfile.dev, it builds the matching local base image and
agent image via ./images/build.sh.

Optional environment variables:
  AGENT            Agent name to build for (default: ACTIVE_AGENT from .agent-sandbox)
  IMAGE_TAG        Docker tag to publish (default: agent-sandbox-dev:<agent>)
  IMAGE_BUILDER    Image build helper (default: ./images/build.sh)
  METADATA_FILE    Agent metadata file (default: ./.agent-sandbox/active-target.env)
  DOCKERFILE_PATH  Dockerfile to build (default: ./Dockerfile.dev)
  BUILD_CONTEXT    Docker build context (default: repo root)
  VERSIONS_FILE    Pinned agent CLI versions (default: ./scripts/dev-image-versions.env)
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

if [ ! -x "$IMAGE_BUILDER" ]; then
	printf 'Image build helper not found or not executable: %s\n' "$IMAGE_BUILDER" >&2
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

if ! is_supported_agent "$AGENT"; then
	printf 'Unsupported agent for local dev image: %s\n' "$AGENT" >&2
	exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-agent-sandbox-dev:$AGENT}"
OVERRIDE_FILE="$REPO_ROOT/.agent-sandbox/compose/user.agent.$AGENT.override.yml"

# Apply pinned agent CLI versions as defaults. images/build.sh defaults these to
# "latest", which is a cache-stable build arg, so Docker reuses the cached
# install layer and never reinstalls the agent. A concrete version busts it.
# Explicitly set environment variables always win over the file.
#
# HERMES_SEMVER only describes the HERMES_VERSION it was recorded with. When the
# caller overrides HERMES_VERSION, skip the pinned semver so images/build.sh
# labels the image from the tag instead of a different release's semver.
HERMES_VERSION_FROM_ENV="${HERMES_VERSION:-}"
if [ -f "$VERSIONS_FILE" ]; then
	while IFS='=' read -r key value; do
		case "$key" in
			'' | \#*) continue ;;
			HERMES_SEMVER)
				if [ -n "$HERMES_VERSION_FROM_ENV" ]; then
					[ -n "${HERMES_SEMVER:-}" ] || printf 'Ignoring pinned HERMES_SEMVER because HERMES_VERSION was set explicitly\n'
					continue
				fi
				;;
		esac
		if [ -z "${!key:-}" ]; then
			export "$key=$value"
			printf 'Pinned %s=%s from %s\n' "$key" "$value" "$VERSIONS_FILE"
		fi
	done < "$VERSIONS_FILE"
fi

printf 'Building prerequisite local images for %s\n' "$AGENT"
"$IMAGE_BUILDER" base "$@"
"$IMAGE_BUILDER" proxy "$@"
"$IMAGE_BUILDER" "$AGENT" "$@"

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
