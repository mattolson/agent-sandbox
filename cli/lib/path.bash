#!/usr/bin/env bash

# shellcheck source=constants.bash
source "$AGB_LIBDIR/constants.bash"

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

# Locates the docker-compose.yml file for the project.
# Checks in priority order:
# 1. $repo_root/$AGB_PROJECT_DIR/docker-compose.yml
# 2. $repo_root/.devcontainer/docker-compose.yml
# Returns the absolute path to the compose file.
# Exits with error if neither file exists.
find_compose_file() {
	local repo_root
	repo_root="$(find_repo_root)"

	local project_compose="$repo_root/$AGB_PROJECT_DIR/docker-compose.yml"
	local devcontainer_compose="$repo_root/.devcontainer/docker-compose.yml"

	if [[ -f "$project_compose" ]]
	then
		echo "$project_compose"
		return 0
	elif [[ -f "$devcontainer_compose" ]]
	then
		echo "$devcontainer_compose"
		return 0
	else
		echo "$0: No docker-compose.yml found at $project_compose or $devcontainer_compose" >&2
		return 1
	fi
}

# Derives a project name from a project path and mode.
# Args:
#   $1 - The project path (absolute or relative)
#   $2 - The mode (cli or devcontainer)
# Returns {dir}-sandbox for cli mode, {dir}-sandbox-{mode} for other modes.
derive_project_name() {
	local project_path=$1
	local mode=$2

	local last_dir
	last_dir=$(basename "$project_path")

	if [[ "$mode" == "cli" ]]
	then
		echo "${last_dir}-sandbox"
	else
		echo "${last_dir}-sandbox-${mode}"
	fi
}

# Gets the modification time of a file in a cross-platform way.
# Args:
#   $1 - The file path
# Returns the modification time as a Unix timestamp
get_file_mtime() {
	local file=$1

	if [[ "$OSTYPE" == "darwin"* ]]; then
		stat -f "%m" "$file"
	else
		stat -c "%Y" "$file"
	fi
}
