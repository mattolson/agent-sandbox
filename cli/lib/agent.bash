#!/usr/bin/env bash

# shellcheck source=constants.bash
source "$AGB_LIBDIR/constants.bash"
# shellcheck source=path.bash
source "$AGB_LIBDIR/path.bash"
# shellcheck source=select.bash
source "$AGB_LIBDIR/select.bash"
# shellcheck source=logging.bash
source "$AGB_LIBDIR/logging.bash"

supported_agents_display() {
        echo "claude codex copilot factory gemini pi"
}

supported_agents() {
        printf '%s\n' claude codex copilot factory gemini pi
}

select_agent() {
        select_option "Select agent:" claude codex copilot factory gemini pi
}

validate_agent() {
        local agent=$1

        case "$agent" in
        claude | copilot | codex | factory | gemini | pi)
                return 0
                ;;
        *)
		echo "Invalid agent: $agent (expected: $(supported_agents_display))" | error
		return 1
		;;
	esac
}

agent_sandbox_dir() {
	local repo_root="${1:-}"

	if [[ -z "$repo_root" ]]
	then
		repo_root="$(find_repo_root)"
	fi

	echo "$repo_root/$AGB_PROJECT_DIR"
}

agent_sandbox_initialized() {
	local repo_root="${1:-}"

	[[ -d "$(agent_sandbox_dir "$repo_root")" ]]
}

active_agent_state_file() {
	local repo_root="${1:-}"

	echo "$(agent_sandbox_dir "$repo_root")/active-target.env"
}

read_target_state_var() {
	local repo_root="${1:-}"
	local var_name=$2
	local state_file
	state_file="$(active_agent_state_file "$repo_root")"

	if [[ ! -f "$state_file" ]]
	then
		return 1
	fi

	(
		unset ACTIVE_AGENT DEVCONTAINER_IDE PROJECT_NAME
		# shellcheck disable=SC1090
		source "$state_file"
		local value="${!var_name:-}"
		[[ -n "$value" ]] || return 1
		printf '%s\n' "$value"
	)
}

read_active_agent() {
	local repo_root="${1:-}"

	read_target_state_var "$repo_root" "ACTIVE_AGENT"
}

read_devcontainer_ide() {
	local repo_root="${1:-}"

	read_target_state_var "$repo_root" "DEVCONTAINER_IDE"
}

read_project_name() {
	local repo_root="${1:-}"

	read_target_state_var "$repo_root" "PROJECT_NAME"
}

write_target_state() {
	local repo_root=$1
	local agent=$2
	local devcontainer_ide="${3:-}"
	local project_name="${4:-}"
	local sandbox_dir
	local state_file
	local tmp_file

	validate_agent "$agent" >/dev/null

	sandbox_dir="$(agent_sandbox_dir "$repo_root")"
	state_file="$(active_agent_state_file "$repo_root")"
	tmp_file="${state_file}.tmp"

	mkdir -p "$sandbox_dir"

	{
		printf '%s\n' \
			"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project."
		printf 'ACTIVE_AGENT=%q\n' "$agent"

		if [[ -n "$devcontainer_ide" ]]
		then
			printf 'DEVCONTAINER_IDE=%q\n' "$devcontainer_ide"
		fi

		if [[ -n "$project_name" ]]
		then
			printf 'PROJECT_NAME=%q\n' "$project_name"
		fi
	} > "$tmp_file"
	replace_file_if_changed "$tmp_file" "$state_file"
}

write_active_agent() {
	local repo_root=$1
	local agent=$2
	local project_name="${3:-}"
	local devcontainer_ide=""

	devcontainer_ide="$(read_devcontainer_ide "$repo_root" 2>/dev/null)" || true
	if [[ -z "$project_name" ]]
	then
		project_name="$(read_project_name "$repo_root" 2>/dev/null)" || true
	fi

	write_target_state "$repo_root" "$agent" "$devcontainer_ide" "$project_name"
}

write_devcontainer_state() {
	local repo_root=$1
	local agent=$2
	local devcontainer_ide=$3
	local project_name=$4

	write_target_state "$repo_root" "$agent" "$devcontainer_ide" "$project_name"
}
