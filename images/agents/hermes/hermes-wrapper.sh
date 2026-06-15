#!/bin/bash
# The canonical hermes entry point. Installed AS the venv console script at
# /opt/hermes/hermes-agent/.venv/bin/hermes (the real script is renamed aside to
# hermes-real) and symlinked from /usr/local/bin/hermes and ~/.local/bin/hermes,
# so every way of invoking `hermes` — PATH lookup, ~/.local/bin, or the full
# venv path — routes through here.
#
# It intercepts the `update` and `uninstall` subcommands. Both would fail anyway
# because the Hermes checkout at /opt/hermes is owned by root and read-only at
# runtime (no editable-source edits, no `git pull`), but the resulting traceback
# reads like a broken tool. The wrapper substitutes a clear message that points
# at the Agent Sandbox image-rebuild upgrade path. All other args pass through to
# hermes-real unchanged (with argv[0] preserved as `hermes`).
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

exec -a hermes /opt/hermes/hermes-agent/.venv/bin/hermes-real "$@"
