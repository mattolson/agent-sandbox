#!/usr/bin/env bash

# Verifies that a file exists in relative path from a directory file.
# Args:
#   $1 - The base directory
#   $2 - The path to verify
verify_relative_path() {
	local base=$1
	local path=$2

	if [[ ! -d "$base" ]]
	then
		echo "$0: base is not a directory: $base" >&2
		return 1
	fi

	if [[ "$path" == /* ]]
	then
		echo "$0: path must be relative, not absolute: $path" >&2
		return 1
	fi

	if [[ ! -f "$base/$path" ]]
	then
		echo "$0: file not found: $base/$path" >&2
		return 1
	fi

	return 0
}
