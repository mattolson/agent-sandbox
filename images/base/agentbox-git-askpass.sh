#!/bin/sh
set -eu

prompt="${1:-}"
prompt_lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"

case "$prompt_lower" in
  *username*)
    printf '%s\n' "${AGENTBOX_GIT_FAKE_USERNAME:-x-access-token}"
    ;;
  *password*)
    printf '%s\n' "${AGENTBOX_GIT_FAKE_PASSWORD:-agentbox-proxy-managed}"
    ;;
  *)
    printf '\n'
    ;;
esac
