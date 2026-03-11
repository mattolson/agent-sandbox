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
	echo "claude copilot codex"
}

select_agent() {
	select_option "Select agent:" claude copilot codex
}

validate_agent() {
	local agent=$1

	case "$agent" in
	claude | copilot | codex)
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

read_active_agent() {
	local repo_root="${1:-}"
	local state_file
	state_file="$(active_agent_state_file "$repo_root")"

	if [[ ! -f "$state_file" ]]
	then
		return 1
	fi

	(
		unset ACTIVE_AGENT
		# shellcheck disable=SC1090
		source "$state_file"
		[[ -n "${ACTIVE_AGENT:-}" ]] || return 1
		printf '%s\n' "$ACTIVE_AGENT"
	)
}

write_active_agent() {
	local repo_root=$1
	local agent=$2
	local sandbox_dir
	local state_file
	local tmp_file

	validate_agent "$agent" >/dev/null

	sandbox_dir="$(agent_sandbox_dir "$repo_root")"
	state_file="$(active_agent_state_file "$repo_root")"
	tmp_file="${state_file}.tmp"

	mkdir -p "$sandbox_dir"

	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=$agent" > "$tmp_file"
	mv "$tmp_file" "$state_file"
}
