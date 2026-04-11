#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
	cat <<'EOF'
Usage: scripts/build-release-artifacts.bash --version <vX.Y.Z> [--out-dir <dir>]

Builds release archives for:
  - darwin/amd64
  - darwin/arm64
  - linux/amd64
  - linux/arm64

Each archive contains:
  - agentbox
  - LICENSE

The script writes:
  - versioned archives and `agentbox_<version>_checksums.txt`
  - stable latest-download archives and `agentbox_checksums.txt`
EOF
}

VERSION=""
OUT_DIR="$REPO_ROOT/dist/release"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--version)
		VERSION="${2:-}"
		shift 2
		;;
	--out-dir)
		OUT_DIR="${2:-}"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [ -z "$VERSION" ]; then
	printf '%s\n' '--version is required' >&2
	usage >&2
	exit 1
fi

case "$VERSION" in
v*) ;;
*)
	printf 'version must start with v, got %s\n' "$VERSION" >&2
	exit 1
	;;
esac

if ! command -v go >/dev/null 2>&1; then
	printf '%s\n' 'go is required' >&2
	exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
	printf '%s\n' 'tar is required' >&2
	exit 1
fi

sha256_line() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1"
		return
	fi

	sha256sum "$1"
}

native_smoke_test() {
	local binary="$1"
	local expected_version="$2"
	local output

	output="$("$binary" version)"
	printf '%s\n' "$output" | grep -F "$expected_version" >/dev/null
	printf '%s\n' "$output" | grep -F 'source: ldflags' >/dev/null
}

metadata_smoke_test() {
	local binary="$1"
	go version -m "$binary" >/dev/null
}

VERSION_NUMBER="${VERSION#v}"
BUILD_COMMIT="${BUILD_COMMIT:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"
BUILD_TIME="${BUILD_TIME:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
if [ -n "${BUILD_DIRTY:-}" ]; then
	DIRTY_VALUE="$BUILD_DIRTY"
elif [ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ]; then
	DIRTY_VALUE=true
else
	DIRTY_VALUE=false
fi

HOST_GOOS="$(go env GOOS)"
HOST_GOARCH="$(go env GOARCH)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$OUT_DIR"
rm -f \
	"$OUT_DIR"/agentbox_"$VERSION_NUMBER"_*.tar.gz \
	"$OUT_DIR"/agentbox_"$VERSION_NUMBER"_checksums.txt \
	"$OUT_DIR"/agentbox_darwin_amd64.tar.gz \
	"$OUT_DIR"/agentbox_darwin_arm64.tar.gz \
	"$OUT_DIR"/agentbox_linux_amd64.tar.gz \
	"$OUT_DIR"/agentbox_linux_arm64.tar.gz \
	"$OUT_DIR"/agentbox_checksums.txt

LD_FLAGS="-X github.com/mattolson/agent-sandbox/internal/version.BuildVersion=$VERSION"
LD_FLAGS="$LD_FLAGS -X github.com/mattolson/agent-sandbox/internal/version.BuildCommit=$BUILD_COMMIT"
LD_FLAGS="$LD_FLAGS -X github.com/mattolson/agent-sandbox/internal/version.BuildTime=$BUILD_TIME"
LD_FLAGS="$LD_FLAGS -X github.com/mattolson/agent-sandbox/internal/version.BuildDirty=$DIRTY_VALUE"

TARGETS=(
	"darwin amd64"
	"darwin arm64"
	"linux amd64"
	"linux arm64"
)

for target in "${TARGETS[@]}"; do
	goos="${target% *}"
	goarch="${target#* }"
	versioned_archive_stem="agentbox_${VERSION_NUMBER}_${goos}_${goarch}"
	latest_archive_stem="agentbox_${goos}_${goarch}"
	versioned_stage_dir="$TMP_DIR/$versioned_archive_stem"
	latest_stage_dir="$TMP_DIR/$latest_archive_stem"
	versioned_archive_path="$OUT_DIR/$versioned_archive_stem.tar.gz"
	latest_archive_path="$OUT_DIR/$latest_archive_stem.tar.gz"
	built_binary="$TMP_DIR/agentbox-${goos}-${goarch}"

	mkdir -p "$versioned_stage_dir" "$latest_stage_dir"
	CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
		go build -trimpath -ldflags "$LD_FLAGS" -o "$built_binary" ./cmd/agentbox
	cp "$built_binary" "$versioned_stage_dir/agentbox"
	cp "$built_binary" "$latest_stage_dir/agentbox"
	cp "$REPO_ROOT/LICENSE" "$versioned_stage_dir/LICENSE"
	cp "$REPO_ROOT/LICENSE" "$latest_stage_dir/LICENSE"

	metadata_smoke_test "$built_binary"
	if [ "$goos" = "$HOST_GOOS" ] && [ "$goarch" = "$HOST_GOARCH" ]; then
		native_smoke_test "$built_binary" "$VERSION"
	fi

	tar -C "$TMP_DIR" -czf "$versioned_archive_path" "$versioned_archive_stem"
	tar -C "$TMP_DIR" -czf "$latest_archive_path" "$latest_archive_stem"
done

versioned_checksum_file="$OUT_DIR/agentbox_${VERSION_NUMBER}_checksums.txt"
latest_checksum_file="$OUT_DIR/agentbox_checksums.txt"
(
	cd "$OUT_DIR"
	: >"$(basename "$versioned_checksum_file")"
	for archive in agentbox_"$VERSION_NUMBER"_*.tar.gz; do
		sha256_line "$archive" >>"$(basename "$versioned_checksum_file")"
	done

	: >"$(basename "$latest_checksum_file")"
	for archive in \
		agentbox_darwin_amd64.tar.gz \
		agentbox_darwin_arm64.tar.gz \
		agentbox_linux_amd64.tar.gz \
		agentbox_linux_arm64.tar.gz; do
		sha256_line "$archive" >>"$(basename "$latest_checksum_file")"
	done
)
printf 'Built release artifacts in %s\n' "$OUT_DIR"
