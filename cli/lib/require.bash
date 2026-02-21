#!/bin/bash
set -euo pipefail

: "${exitcode_expectation_failed:=168}"

# Ensures a command is available
# Args:
#   $1 - The command name to require
# Returns:
#   0 if command is available or successfully shimmed, non-zero otherwise
require() {
	local -r cmd="$1"

	if ! command -v "$cmd" &>/dev/null
	then
		>&2 echo "$0: $cmd required"
		return "$exitcode_expectation_failed"
	fi
}
