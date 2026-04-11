#!/bin/sh
set -eu

usage() {
	cat <<'EOF'
Usage: install-agentbox.sh [--version <vX.Y.Z>] [--install-dir <dir>] [--base-url <url>]

Installs agentbox from GitHub Releases.

Defaults:
  version     latest release
  install dir $HOME/.local/bin
  base url    https://github.com/mattolson/agent-sandbox/releases

Examples:
  sh install-agentbox.sh
  sh install-agentbox.sh --version v0.13.0
  sh install-agentbox.sh --install-dir /usr/local/bin
EOF
}

require_command() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf 'required command not found: %s\n' "$1" >&2
		exit 1
	fi
}

sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
		return
	fi

	sha256sum "$1" | awk '{print $1}'
}

normalize_version() {
	case "$1" in
	v*) printf '%s\n' "$1" ;;
	*) printf 'v%s\n' "$1" ;;
	esac
}

VERSION=""
INSTALL_DIR="${HOME}/.local/bin"
BASE_URL="${AGENTBOX_RELEASE_BASE_URL:-https://github.com/mattolson/agent-sandbox/releases}"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--version)
		VERSION="${2:-}"
		shift 2
		;;
	--install-dir)
		INSTALL_DIR="${2:-}"
		shift 2
		;;
	--base-url)
		BASE_URL="${2:-}"
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

require_command curl
require_command tar
require_command install
require_command uname
require_command mktemp

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

case "$arch" in
	x86_64 | amd64) arch="amd64" ;;
	arm64 | aarch64) arch="arm64" ;;
	*)
		printf 'unsupported architecture: %s\n' "$arch" >&2
		exit 1
		;;
esac

asset="agentbox_${os}_${arch}.tar.gz"
checksum_asset="agentbox_checksums.txt"
archive_dir="${asset%.tar.gz}"

if [ -n "$VERSION" ]; then
	version_tag="$(normalize_version "$VERSION")"
	version_number="${version_tag#v}"
	asset="agentbox_${version_number}_${os}_${arch}.tar.gz"
	checksum_asset="agentbox_${version_number}_checksums.txt"
	archive_dir="${asset%.tar.gz}"
	asset_url="${BASE_URL}/download/${version_tag}/${asset}"
	checksum_url="${BASE_URL}/download/${version_tag}/${checksum_asset}"
else
	asset_url="${BASE_URL}/latest/download/${asset}"
	checksum_url="${BASE_URL}/latest/download/${checksum_asset}"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

cd "$tmp_dir"
curl -fsSLo "$asset" "$asset_url"
curl -fsSLo "$checksum_asset" "$checksum_url"

expected_checksum="$(awk -v asset="$asset" '$2 == asset {print $1}' "$checksum_asset")"
if [ -z "$expected_checksum" ]; then
	printf 'failed to find checksum for %s in %s\n' "$asset" "$checksum_asset" >&2
	exit 1
fi

actual_checksum="$(sha256_file "$asset")"
if [ "$expected_checksum" != "$actual_checksum" ]; then
	printf 'checksum mismatch for %s\n' "$asset" >&2
	printf 'expected: %s\n' "$expected_checksum" >&2
	printf 'actual:   %s\n' "$actual_checksum" >&2
	exit 1
fi

tar -xzf "$asset"

mkdir -p "$INSTALL_DIR"
install -m 755 "${archive_dir}/agentbox" "${INSTALL_DIR}/agentbox"

printf 'Installed agentbox to %s/agentbox\n' "$INSTALL_DIR"
"${INSTALL_DIR}/agentbox" version

case ":${PATH}:" in
*:"${INSTALL_DIR}":*) ;;
*)
	printf '\n%s\n' "Add ${INSTALL_DIR} to your PATH if it is not already there."
	;;
esac
