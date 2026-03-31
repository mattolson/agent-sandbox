#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$REPO_ROOT/cli/templates"
DEST_DIR="$REPO_ROOT/internal/embeddata/templates"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ ! -d "$SOURCE_DIR" ]; then
	printf 'source template directory not found: %s\n' "$SOURCE_DIR" >&2
	exit 1
fi

mkdir -p "$TMP_DIR/templates"
cp -R "$SOURCE_DIR/." "$TMP_DIR/templates/"
rm -rf "$DEST_DIR"
mkdir -p "$(dirname "$DEST_DIR")"
mv "$TMP_DIR/templates" "$DEST_DIR"

printf 'Synced Go embedded templates from %s to %s\n' "$SOURCE_DIR" "$DEST_DIR"
