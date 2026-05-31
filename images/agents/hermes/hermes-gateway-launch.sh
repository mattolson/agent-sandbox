#!/bin/sh
# Default command for the Hermes image.
#
# Starts `hermes gateway run` in the background, then hands the container's
# main process to `sleep infinity`. This deliberately decouples the
# container's lifetime from the gateway: if the gateway exits or crashes,
# the container stays up so `agentbox exec` keeps working and the gateway
# can be restarted (re-run this script, or `hermes gateway run` by hand).
#
# The gateway inherits this process's stdout/stderr, so its logs surface in
# `agentbox logs agent`. `hermes` resolves to the /usr/local/bin/hermes
# wrapper on PATH (update/uninstall interception stays intact).
set -e

hermes gateway run &

exec sleep infinity
