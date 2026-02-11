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

# Finds the repository root directory by walking up the directory tree.
# Looks for $AGB_PROJECT_DIR directory, .git directory, or .devcontainer directory.
# Returns the absolute path to the root directory.
find_repo_root() {
	local current_dir="${1:-$PWD}"

	while [[ "$current_dir" != "/" ]]
	do
		if [[ -d "$current_dir/$AGB_PROJECT_DIR" ]] || \
		   [[ -d "$current_dir/.git" ]] || \
		   [[ -d "$current_dir/.devcontainer" ]]
		then
			echo "$current_dir"
			return 0
		fi

		current_dir="$(dirname "$current_dir")"
	done

	echo "$0: repository root not found" >&2
	return 1
}
