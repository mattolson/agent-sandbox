#!/bin/sh
# Wrapper around /opt/hermes/.venv/bin/hermes that intercepts the
# `update` and `uninstall` subcommands. Both would fail anyway because
# the Hermes venv at /opt/hermes/.venv is owned by root and read-only
# at runtime, but pip's EACCES traceback reads like a broken tool. The
# wrapper substitutes a clear message that points at the Agent Sandbox
# image-rebuild upgrade path. All other args pass through unchanged.
#
# HERMES_MANAGED is deliberately NOT set in the image: it would block
# `hermes setup` and require pre-existing state subdirectories that the
# normal first-run path creates on its own.

set -e

case "$1" in
    update|uninstall)
        cat >&2 <<'MSG'
hermes update/uninstall is disabled in Agent Sandbox: the Hermes venv
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

exec /opt/hermes/.venv/bin/hermes "$@"
