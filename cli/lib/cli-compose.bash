#!/usr/bin/env bash

# shellcheck source=agent.bash
source "$AGB_LIBDIR/agent.bash"
# shellcheck source=composefile.bash
source "$AGB_LIBDIR/composefile.bash"
# shellcheck source=constants.bash
source "$AGB_LIBDIR/constants.bash"
# shellcheck source=logging.bash
source "$AGB_LIBDIR/logging.bash"
# shellcheck source=path.bash
source "$AGB_LIBDIR/path.bash"
# shellcheck source=policyfile.bash
source "$AGB_LIBDIR/policyfile.bash"

cli_compose_dir() {
	local repo_root="${1:-}"

	if [[ -z "$repo_root" ]]
	then
		repo_root="$(find_repo_root)"
	fi

	echo "$repo_root/$AGB_PROJECT_DIR/compose"
}

cli_base_compose_file() {
	local repo_root="${1:-}"

	echo "$(cli_compose_dir "$repo_root")/base.yml"
}

cli_agent_compose_file() {
	local repo_root=$1
	local agent=$2

	validate_agent "$agent" >/dev/null
	echo "$(cli_compose_dir "$repo_root")/agent.$agent.yml"
}

cli_devcontainer_mode_compose_file() {
	local repo_root="${1:-}"

	echo "$(cli_compose_dir "$repo_root")/mode.devcontainer.yml"
}

cli_user_override_file() {
	local repo_root="${1:-}"

	echo "$(cli_compose_dir "$repo_root")/user.override.yml"
}

cli_user_agent_override_file() {
	local repo_root=$1
	local agent=$2

	validate_agent "$agent" >/dev/null
	echo "$(cli_compose_dir "$repo_root")/user.agent.$agent.override.yml"
}

cli_policy_dir() {
	local repo_root="${1:-}"

	if [[ -z "$repo_root" ]]
	then
		repo_root="$(find_repo_root)"
	fi

	echo "$repo_root/$AGB_PROJECT_DIR/policy"
}

cli_shared_policy_file() {
	local repo_root="${1:-}"

	echo "$(cli_policy_dir "$repo_root")/user.policy.yaml"
}

cli_user_agent_policy_file() {
	local repo_root=$1
	local agent=$2

	validate_agent "$agent" >/dev/null
	echo "$(cli_policy_dir "$repo_root")/user.agent.$agent.policy.yaml"
}

cli_legacy_policy_file() {
	local repo_root=$1
	local agent=$2

	validate_agent "$agent" >/dev/null
	echo "$repo_root/$AGB_PROJECT_DIR/policy-cli-$agent.yaml"
}

cli_layered_compose_initialized() {
	local repo_root="${1:-}"

	[[ -f "$(cli_base_compose_file "$repo_root")" ]]
}

emit_cli_compose_files() {
	local repo_root=$1
	local agent="${2:-}"
	local base_file
	local agent_file
	local shared_override
	local agent_override

	if [[ -z "$agent" ]]
	then
		agent="$(read_active_agent "$repo_root")" || {
			echo "Active agent state missing for layered CLI compose at $repo_root. Run 'agentbox switch --agent <name>'." | error
			return 1
		}
	fi

	validate_agent "$agent" >/dev/null

	base_file="$(cli_base_compose_file "$repo_root")"
	agent_file="$(cli_agent_compose_file "$repo_root" "$agent")"
	shared_override="$(cli_user_override_file "$repo_root")"
	agent_override="$(cli_user_agent_override_file "$repo_root" "$agent")"

	if [[ ! -f "$base_file" ]]
	then
		echo "Layered CLI compose base file not found: $base_file" | error
		return 1
	fi

	if [[ ! -f "$agent_file" ]]
	then
		echo "Layered CLI compose agent file not found for '$agent': $agent_file" | error
		return 1
	fi

	printf '%s\n' "$base_file"
	printf '%s\n' "$agent_file"

	if [[ -f "$shared_override" ]]
	then
		printf '%s\n' "$shared_override"
	fi

	if [[ -f "$agent_override" ]]
	then
		printf '%s\n' "$agent_override"
	fi
}

write_cli_base_compose_file() {
	local repo_root=$1
	local project_name=$2
	local proxy_image=$3
	local compose_dir
	local base_file

	compose_dir="$(cli_compose_dir "$repo_root")"
	base_file="$(cli_base_compose_file "$repo_root")"

	mkdir -p "$compose_dir"
	cp "$AGB_TEMPLATEDIR/compose/base.yml" "$base_file"

	set_proxy_image "$base_file" "$proxy_image"
	set_project_name "$base_file" "$project_name"
	ensure_cli_base_policy_runtime_config "$repo_root"
}

scaffold_cli_base_compose() {
	local repo_root=$1
	local project_name=$2
	local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	local proxy_image_pinned

	proxy_image_pinned=$(pull_and_pin_image "${AGENTBOX_PROXY_IMAGE:-$default_proxy_image}")
	write_cli_base_compose_file "$repo_root" "$project_name" "$proxy_image_pinned"
}

write_cli_agent_compose_file() {
	local repo_root=$1
	local agent=$2
	local agent_image=$3
	local compose_dir
	local agent_file
	local template_file

	validate_agent "$agent" >/dev/null

	compose_dir="$(cli_compose_dir "$repo_root")"
	agent_file="$(cli_agent_compose_file "$repo_root" "$agent")"
	template_file="$AGB_TEMPLATEDIR/$agent/cli/agent.yml"

	mkdir -p "$compose_dir"
	cp "$template_file" "$agent_file"

	set_agent_image "$agent_file" "$agent_image"
	ensure_cli_agent_policy_runtime_config "$repo_root" "$agent"
}

scaffold_cli_agent_compose() {
	local repo_root=$1
	local agent=$2
	local overwrite="${3:-false}"
	local allow_env_override="${4:-true}"
	local compose_dir
	local agent_file
	local template_file
	local default_agent_image
	local agent_image
	local agent_image_pinned

	validate_agent "$agent" >/dev/null

	compose_dir="$(cli_compose_dir "$repo_root")"
	agent_file="$(cli_agent_compose_file "$repo_root" "$agent")"
	template_file="$AGB_TEMPLATEDIR/$agent/cli/agent.yml"

	if [[ "$overwrite" != "true" ]] && [[ -f "$agent_file" ]]
	then
		ensure_cli_agent_policy_runtime_config "$repo_root" "$agent"
		return 0
	fi

	default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"

	if [[ "$allow_env_override" == "true" ]]
	then
		agent_image="${AGENTBOX_AGENT_IMAGE:-$default_agent_image}"
	else
		agent_image="$default_agent_image"
	fi

	agent_image_pinned=$(pull_and_pin_image "$agent_image")
	write_cli_agent_compose_file "$repo_root" "$agent" "$agent_image_pinned"
}

scaffold_cli_shared_override_if_missing() {
	local repo_root=$1
	local override_file

	override_file="$(cli_user_override_file "$repo_root")"

	if [[ -f "$override_file" ]]
	then
		return 0
	fi

	mkdir -p "$(dirname "$override_file")"
	cp "$AGB_TEMPLATEDIR/compose/user.override.yml" "$override_file"

	: "${AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS:=false}"
	: "${AGENTBOX_ENABLE_DOTFILES:=false}"
	: "${AGENTBOX_MOUNT_GIT_READONLY:=false}"
	: "${AGENTBOX_MOUNT_IDEA_READONLY:=false}"
	: "${AGENTBOX_MOUNT_VSCODE_READONLY:=false}"

	if [[ "$AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS" == "true" ]]
	then
		add_volume_entry "$override_file" '${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro' "true"
	fi

	if [[ "$AGENTBOX_ENABLE_DOTFILES" == "true" ]]
	then
		add_volume_entry "$override_file" '${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro' "true"
	fi

	if [[ "$AGENTBOX_MOUNT_GIT_READONLY" == "true" ]]
	then
		add_volume_entry "$override_file" '../../.git:/workspace/.git:ro' "true"
	fi

	if [[ "$AGENTBOX_MOUNT_IDEA_READONLY" == "true" ]]
	then
		add_volume_entry "$override_file" '../../.idea:/workspace/.idea:ro' "true"
	fi

	if [[ "$AGENTBOX_MOUNT_VSCODE_READONLY" == "true" ]]
	then
		add_volume_entry "$override_file" '../../.vscode:/workspace/.vscode:ro' "true"
	fi
}

scaffold_cli_agent_override_if_missing() {
	local repo_root=$1
	local agent=$2
	local override_file

	validate_agent "$agent" >/dev/null
	override_file="$(cli_user_agent_override_file "$repo_root" "$agent")"

	if [[ -f "$override_file" ]]
	then
		return 0
	fi

	mkdir -p "$(dirname "$override_file")"
	cp "$AGB_TEMPLATEDIR/compose/user.agent.override.yml" "$override_file"

	if [[ "$agent" == "claude" ]]
	then
		: "${AGENTBOX_MOUNT_CLAUDE_CONFIG:=false}"

		if [[ "$AGENTBOX_MOUNT_CLAUDE_CONFIG" == "true" ]]
		then
			# shellcheck disable=SC2016
			add_volume_entry "$override_file" '${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro' "true"
			# shellcheck disable=SC2016
			add_volume_entry "$override_file" '${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro' "true"
		fi
	fi
}

ensure_cli_policy_file() {
	local repo_root=$1
	local agent=$2
	local policy_file

	validate_agent "$agent" >/dev/null
	policy_file="$(cli_user_agent_policy_file "$repo_root" "$agent")"

	if [[ -f "$policy_file" ]]
	then
		return 0
	fi

	scaffold_user_policy_file_if_missing "$policy_file" "user.agent.policy.yaml"
}

ensure_cli_base_policy_runtime_config() {
	local repo_root=$1
	local base_file
	local shared_relative

	base_file="$(cli_base_compose_file "$repo_root")"
	shared_relative="../policy/$(basename "$(cli_shared_policy_file "$repo_root")")"

	if [[ ! -f "$base_file" ]]
	then
		return 1
	fi

	ensure_proxy_volume "$base_file" "$shared_relative:/etc/agent-sandbox/policy/user.policy.yaml:ro"
}

ensure_cli_agent_policy_runtime_config() {
	local repo_root=$1
	local agent=$2
	local agent_file
	local legacy_volume
	local policy_relative

	validate_agent "$agent" >/dev/null
	agent_file="$(cli_agent_compose_file "$repo_root" "$agent")"
	legacy_volume="../$(basename "$(cli_legacy_policy_file "$repo_root" "$agent")"):/etc/mitmproxy/policy.yaml:ro"
	policy_relative="../policy/$(basename "$(cli_user_agent_policy_file "$repo_root" "$agent")")"

	if [[ ! -f "$agent_file" ]]
	then
		return 1
	fi

	remove_proxy_volume "$agent_file" "$legacy_volume"
	ensure_proxy_volume "$agent_file" "$policy_relative:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro"
	set_proxy_environment_var "$agent_file" "AGENTBOX_ACTIVE_AGENT" "$agent"
}

scaffold_cli_shared_policy_if_missing() {
	local repo_root=$1
	local policy_file

	policy_file="$(cli_shared_policy_file "$repo_root")"
	scaffold_user_policy_file_if_missing "$policy_file" "user.policy.yaml"
}

initialize_cli_layered_layout() {
	local repo_root=$1
	local agent=$2
	local project_name=$3

	validate_agent "$agent" >/dev/null

	scaffold_cli_base_compose "$repo_root" "$project_name"
	scaffold_cli_shared_override_if_missing "$repo_root"
	scaffold_cli_shared_policy_if_missing "$repo_root"
	ensure_cli_policy_file "$repo_root" "$agent"
	scaffold_cli_agent_compose "$repo_root" "$agent" "true" "true"
	scaffold_cli_agent_override_if_missing "$repo_root" "$agent"
}

ensure_cli_agent_runtime_files() {
	local repo_root=$1
	local agent=$2
	local skip_agent_compose="${3:-false}"

	validate_agent "$agent" >/dev/null

	ensure_cli_base_policy_runtime_config "$repo_root" || true
	scaffold_cli_shared_override_if_missing "$repo_root"
	scaffold_cli_shared_policy_if_missing "$repo_root"
	ensure_cli_policy_file "$repo_root" "$agent"
	if [[ "$skip_agent_compose" != "true" ]]
	then
		scaffold_cli_agent_compose "$repo_root" "$agent" "false" "false"
	fi
	scaffold_cli_agent_override_if_missing "$repo_root" "$agent"
}
