#!/bin/bash
# Link image-baked Agent Sandbox skills into the agent's skill-discovery dirs.
#
# Runs as the dev user at container startup via entrypoint.sh, after
# link-dotfiles.sh so user-provided skills are already in place. Idempotent.
#
# `.agents/skills` is the cross-agent convention; Claude reads `.claude/skills`
# instead. We create a per-skill symlink in both home locations (the .claude one
# is unused by non-Claude agents, but harmless). Per-skill symlinks let our
# skills coexist with any the user supplies via dotfiles.

set -uo pipefail

SKILLS_SRC="/usr/local/share/agent-sandbox/skills"

# No-op if nothing is baked into the image.
[ -d "$SKILLS_SRC" ] || exit 0

DEST_DIRS=("$HOME/.agents/skills" "$HOME/.claude/skills")

for src in "$SKILLS_SRC"/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"

  for dest_dir in "${DEST_DIRS[@]}"; do
    link="$dest_dir/$name"

    # Never clobber a real entry (e.g. a user's own same-named skill).
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      echo "skills: $link exists and is not a symlink; leaving it alone" >&2
      continue
    fi

    if ! mkdir -p "$dest_dir" 2>/dev/null; then
      echo "skills: cannot create $dest_dir; skipping $name" >&2
      continue
    fi

    # -n so an existing symlink is replaced rather than dereferenced into.
    if ! ln -sfn "$SKILLS_SRC/$name" "$link" 2>/dev/null; then
      echo "skills: failed to link $link" >&2
    fi
  done
done
