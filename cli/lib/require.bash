#!/bin/bash
set -euo pipefail
shopt -s inherit_errexit lastpipe

# Ensures a command is available, optionally shimming it via Docker if supported.
# If the command is not found and a shim exists, creates a function that runs
# the command in a Docker container. If no shim exists, returns an error.
# Args:
#   $1 - The command name to require
# Returns:
#   0 if command is available or successfully shimmed, non-zero otherwise
require() {
	local -r cmd="$1"
	declare -A shims=([yq]=mikefarah/yq)

	if ! command -v "$cmd" &>/dev/null
	then
		if [[ -v shims[$cmd] ]] && command -v docker &>/dev/null
		then
			>&2 echo "$0: $cmd not found, using Docker cmd"
			docker pull --quiet "${shims[$cmd]}"
			eval "$cmd"'() {
					docker run \
						--rm \
						--interactive \
						--volume "$PWD:$PWD" \
						--workdir "$PWD" \
						--user "$(id -u):$(id -g)" \
						--network=host \
						'"${shims[$cmd]}"' "$@"
				}'
			local output
			if ! output=$("$cmd" --version 2>&1)
			then
				>&2 echo "$0: $cmd failed to run"
				>&2 echo "$output"
				unset "$cmd"
				return "$exitcode_expectation_failed"
			fi
		else
			>&2 echo "$0: $cmd required"
			return "$exitcode_expectation_failed"
		fi
	fi
}

: "${exitcode_expectation_failed:=168}"
