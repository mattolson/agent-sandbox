#!/bin/bash
# Auto-symlink dotfiles from ~/.dotfiles into $HOME
# Runs as the dev user at container startup via entrypoint.sh
#
# Recursively walks ~/.dotfiles and creates symlinks for each regular file
# at the corresponding path under $HOME. Creates intermediate directories
# as needed. Skips protected prefixes and .git directories.

set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles"

# No-op if dotfiles directory is not mounted
[ -d "$DOTFILES_DIR" ] || exit 0

# Prefixes where symlinking is skipped (root-owned, must not be modified)
PROTECTED_PREFIXES=".config/agent-sandbox"

find "$DOTFILES_DIR" -name .git -prune -o -type f -print | while read -r source; do
  relpath="${source#$DOTFILES_DIR/}"

  # Skip protected prefixes
  skip=false
  for prefix in $PROTECTED_PREFIXES; do
    case "$relpath" in
      "$prefix"|"$prefix"/*) skip=true; break ;;
    esac
  done
  $skip && continue

  target="$HOME/$relpath"

  # Create parent directories if needed
  mkdir -p "$(dirname "$target")"

  # Create symlink (ignore failures from bind-mount conflicts)
  ln -sf "$source" "$target" 2>/dev/null || true
done
