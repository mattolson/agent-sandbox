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

# Locates the primary compose file for the project.
# Checks in priority order:
# 1. $repo_root/$AGB_PROJECT_DIR/docker-compose.yml
# 2. $repo_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml
# 3. $repo_root/.devcontainer/docker-compose.yml
# Returns the absolute path to the primary compose file.
# Exits with error if none of the supported paths exist.
find_compose_file() {
	local repo_root
	repo_root="$(find_repo_root)"

	local project_compose="$repo_root/$AGB_PROJECT_DIR/docker-compose.yml"
	local devcontainer_mode_compose="$repo_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml"
	local devcontainer_compose="$repo_root/.devcontainer/docker-compose.yml"

	if [[ -f "$project_compose" ]]
	then
		echo "$project_compose"
		return 0
	elif [[ -f "$devcontainer_mode_compose" ]]
	then
		echo "$devcontainer_mode_compose"
		return 0
	elif [[ -f "$devcontainer_compose" ]]
	then
		echo "$devcontainer_compose"
		return 0
	else
		echo "$0: No compose file found at $project_compose, $devcontainer_mode_compose, or $devcontainer_compose" >&2
		return 1
	fi
}

# Derives a base project name from a project path (without mode suffix).
# Args:
#   $1 - The project path (absolute or relative)
# Returns {dir}-sandbox
derive_base_project_name() {
	local project_path=$1
	local last_dir
	last_dir=$(basename "$project_path")
	echo "${last_dir}-sandbox"
}

# Applies mode suffix to a project name.
# Args:
#   $1 - The base project name
#   $2 - The mode (cli or devcontainer)
# Returns the name as-is for cli mode, {name}-{mode} for other modes.
apply_mode_suffix() {
	local name=$1
	local mode=$2

	if [[ "$mode" == "cli" ]]
	then
		echo "$name"
	else
		echo "${name}-${mode}"
	fi
}

# Removes a trailing mode suffix from a project name when present.
# Args:
#   $1 - The project name
#   $2 - The mode (cli or devcontainer)
# Returns the name without the trailing -{mode} suffix, or the original name if absent.
strip_mode_suffix() {
	local name=$1
	local mode=$2
	local suffix="-$mode"

	if [[ "$mode" == "cli" ]]
	then
		echo "$name"
	elif [[ "$name" == *"$suffix" ]]
	then
		echo "${name%"$suffix"}"
	else
		echo "$name"
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

	local base_name
	base_name=$(derive_base_project_name "$project_path")
	apply_mode_suffix "$base_name" "$mode"
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

replace_file_if_changed() {
	local tmp_file=$1
	local target_file=$2

	if [[ -f "$target_file" ]] && cmp -s "$tmp_file" "$target_file"
	then
		rm -f "$tmp_file"
		return 0
	fi

	mv "$tmp_file" "$target_file"
}
