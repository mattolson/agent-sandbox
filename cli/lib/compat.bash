#!/bin/bash
# Bash 3 compatibility shims

# mapfile/readarray shim for bash < 4
# Registers if mapfile is not available OR when running bats tests
# Requires -t flag (strip trailing newlines)
if ! command -v mapfile &>/dev/null || [[ -n "${BATS_VERSION-}" ]]
then
	mapfile() {
		if [[ "${1-}" != "-t" ]]
		then
			echo "mapfile: -t flag is required" >&2
			return 1
		fi
		shift

		local v="${1:-MAPFILE}"

		local i=0
		local line
		while IFS= read -r line
		do
			IFS= read -r "${v}[${i}]" <<<"$line"
			: $((i++))
		done
	}
fi
