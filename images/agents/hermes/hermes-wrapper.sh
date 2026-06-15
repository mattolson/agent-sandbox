#!/bin/sh
# Wrapper around /opt/hermes/hermes-agent/.venv/bin/hermes that intercepts the
# `update` and `uninstall` subcommands. The Hermes checkout at /opt/hermes is
# root-owned and read-only at runtime (no editable-source edits, no `git pull`),
# so a real update would fail with a confusing git/EACCES traceback; the wrapper
# substitutes a clear message pointing at the image-rebuild upgrade path. All
# other args pass straight through to the real entry point unchanged.
#
# Installed ONLY at /usr/local/bin/hermes (on PATH). The image deliberately does
# not plant ~/.local/bin/hermes, even though `hermes doctor`'s "Command
# Installation" check expects it: pointing that symlink at the real venv binary
# (what doctor wants) would shadow this wrapper when ~/.local/bin is ahead on
# PATH and let `update`/`uninstall` slip through, while making the wrapper itself
# the venv entry point (the other way to satisfy doctor) renames the binary and
# breaks `hermes gateway` status detection, which scans process command lines for
# ".../hermes gateway". So we leave the real entry point untouched and accept
# doctor's one cosmetic "missing symlink" note. See docs/agents/hermes.md.
#
# HERMES_MANAGED is deliberately NOT set in the image: it would block
# `hermes setup` and require pre-existing state subdirectories that the
# normal first-run path creates on its own.

set -e

case "$1" in
    update|uninstall)
        cat >&2 <<'MSG'
hermes update/uninstall is disabled in Agent Sandbox: the Hermes checkout
is baked into the image and read-only at runtime. To upgrade, rebuild
the image:

    # on the host
    agentbox bump
    agentbox down && agentbox up

Your HERMES_HOME volume persists across the swap. See
docs/agents/hermes.md for the full upgrade path.
MSG
        exit 1
        ;;
esac

exec /opt/hermes/hermes-agent/.venv/bin/hermes "$@"
