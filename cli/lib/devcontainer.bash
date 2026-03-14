#!/usr/bin/env bash

# shellcheck source=agent.bash
source "$AGB_LIBDIR/agent.bash"
# shellcheck source=cli-compose.bash
source "$AGB_LIBDIR/cli-compose.bash"
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

supported_ides_display() {
	echo "vscode jetbrains none"
}

validate_devcontainer_ide() {
	local ide=$1

	case "$ide" in
	vscode | jetbrains | none)
		return 0
		;;
	*)
		echo "Invalid IDE: $ide (expected: $(supported_ides_display))" | error
		return 1
		;;
	esac
}

devcontainer_dir() {
	local repo_root="${1:-}"

	if [[ -z "$repo_root" ]]
	then
		repo_root="$(find_repo_root)"
	fi

	echo "$repo_root/.devcontainer"
}

devcontainer_compose_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/docker-compose.base.yml"
}

devcontainer_legacy_compose_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/docker-compose.yml"
}

devcontainer_user_compose_override_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/docker-compose.user.override.yml"
}

devcontainer_json_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/devcontainer.json"
}

devcontainer_user_json_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/devcontainer.user.json"
}

devcontainer_policy_override_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/policy.override.yaml"
}

devcontainer_user_policy_override_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/policy.user.override.yaml"
}

devcontainer_sidecar_initialized() {
	local repo_root="${1:-}"

	[[ -f "$(devcontainer_compose_file "$repo_root")" ]]
}

emit_devcontainer_compose_files() {
	local repo_root="${1:-}"
	local managed_file
	local user_file

	managed_file="$(devcontainer_compose_file "$repo_root")"
	user_file="$(devcontainer_user_compose_override_file "$repo_root")"

	if [[ ! -f "$managed_file" ]]
	then
		echo "Devcontainer compose file not found: $managed_file" | error
		return 1
	fi

	printf '%s\n' "$managed_file"

	if [[ -f "$user_file" ]]
	then
		printf '%s\n' "$user_file"
	fi
}

scaffold_devcontainer_user_json_if_missing() {
	local repo_root=$1
	local user_file

	user_file="$(devcontainer_user_json_file "$repo_root")"

	if [[ -f "$user_file" ]]
	then
		return 0
	fi

	mkdir -p "$(dirname "$user_file")"
	cp "$AGB_TEMPLATEDIR/devcontainer/devcontainer.user.json" "$user_file"
}

scaffold_devcontainer_user_policy_override_if_missing() {
	local repo_root=$1
	local policy_file

	policy_file="$(devcontainer_user_policy_override_file "$repo_root")"

	if [[ -f "$policy_file" ]]
	then
		return 0
	fi

	scaffold_user_policy_file_if_missing "$policy_file" "devcontainer/policy.user.override.yaml"
}

scaffold_devcontainer_user_compose_override_if_missing() {
	local repo_root=$1
	local agent=$2
	local ide=$3
	local override_file

	validate_agent "$agent" >/dev/null
	validate_devcontainer_ide "$ide" >/dev/null

	override_file="$(devcontainer_user_compose_override_file "$repo_root")"

	if [[ -f "$override_file" ]]
	then
		return 0
	fi

	mkdir -p "$(dirname "$override_file")"
	cp "$AGB_TEMPLATEDIR/devcontainer/docker-compose.user.override.yml" "$override_file"

	if [[ "$agent" == "claude" ]]
	then
		: "${AGENTBOX_MOUNT_CLAUDE_CONFIG:=false}"
	fi

	: "${AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS:=false}"
	: "${AGENTBOX_ENABLE_DOTFILES:=false}"
	: "${AGENTBOX_MOUNT_GIT_READONLY:=false}"

	if [[ "$ide" == "jetbrains" ]]
	then
		: "${AGENTBOX_MOUNT_IDEA_READONLY:=true}"
	fi

	if [[ "$ide" == "vscode" ]]
	then
		: "${AGENTBOX_MOUNT_VSCODE_READONLY:=true}"
	fi

	if [[ "$agent" == "claude" ]] && [[ "$AGENTBOX_MOUNT_CLAUDE_CONFIG" == "true" ]]
	then
		# shellcheck disable=SC2016
		add_volume_entry "$override_file" '${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro' "true"
		# shellcheck disable=SC2016
		add_volume_entry "$override_file" '${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro' "true"
	fi

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
		add_volume_entry "$override_file" '../.git:/workspace/.git:ro' "true"
	fi

	if [[ "${AGENTBOX_MOUNT_IDEA_READONLY:-false}" == "true" ]]
	then
		add_volume_entry "$override_file" '../.idea:/workspace/.idea:ro' "true"
	fi

	if [[ "${AGENTBOX_MOUNT_VSCODE_READONLY:-false}" == "true" ]]
	then
		add_volume_entry "$override_file" '../.vscode:/workspace/.vscode:ro' "true"
	fi
}

devcontainer_template_json_file() {
	local agent=$1

	validate_agent "$agent" >/dev/null
	echo "$AGB_TEMPLATEDIR/$agent/devcontainer/devcontainer.json"
}

devcontainer_template_compose_file() {
	local agent=$1

	validate_agent "$agent" >/dev/null
	echo "$AGB_TEMPLATEDIR/$agent/devcontainer/docker-compose.base.yml"
}

render_devcontainer_json() {
	local repo_root=$1
	local agent=$2
	local output_file=$3
	local user_file
	local template_file
	local tmp_file

	validate_agent "$agent" >/dev/null
	require yq

	user_file="$(devcontainer_user_json_file "$repo_root")"
	template_file="$(devcontainer_template_json_file "$agent")"
	tmp_file="${output_file}.tmp"

	if [[ -f "$user_file" ]]
	then
		yq eval-all -P -o=json \
			'select(fileIndex == 0) * select(fileIndex == 1)' \
			"$template_file" \
			"$user_file" > "$tmp_file"
	else
		cp "$template_file" "$tmp_file"
	fi

	mv "$tmp_file" "$output_file"
}

read_compose_service_image_if_exists() {
	local compose_file=$1
	local service=$2

	require yq

	if [[ ! -f "$compose_file" ]]
	then
		return 1
	fi

	service="$service" yq -r '.services.[env(service)].image // ""' "$compose_file"
}

write_devcontainer_policy_override_file() {
	local policy_file=$1
	local ide=$2
	local services=""

	validate_devcontainer_ide "$ide" >/dev/null
	require yq

	copy_policy_template "$policy_file" "devcontainer/policy.override.yaml"

	if [[ "$ide" != "none" ]]
	then
		services="$ide"
	fi

	services="$services" yq -i \
		'.services = ((strenv(services) | split("\n")) | map(select(. != "")))' \
		"$policy_file"
}

write_devcontainer_compose_file() {
	local repo_root=$1
	local agent=$2
	local ide=$3
	local project_name=$4
	local proxy_image=$5
	local agent_image=$6
	local compose_file
	local template_file

	validate_agent "$agent" >/dev/null
	validate_devcontainer_ide "$ide" >/dev/null

	compose_file="$(devcontainer_compose_file "$repo_root")"
	template_file="$(devcontainer_template_compose_file "$agent")"

	mkdir -p "$(dirname "$compose_file")"
	cp "$template_file" "$compose_file"

	set_project_name "$compose_file" "$project_name"
	set_proxy_image "$compose_file" "$proxy_image"
	set_agent_image "$compose_file" "$agent_image"

	if [[ "$ide" == "jetbrains" ]]
	then
		add_jetbrains_capabilities "$compose_file"
	fi
}

initialize_devcontainer_sidecar_layout() {
	local repo_root=$1
	local agent=$2
	local ide=$3
	local project_name=$4
	local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	local default_agent_image
	local proxy_image_pinned
	local agent_image_pinned

	validate_agent "$agent" >/dev/null
	validate_devcontainer_ide "$ide" >/dev/null

	default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"

	scaffold_cli_shared_policy_if_missing "$repo_root"
	ensure_cli_policy_file "$repo_root" "$agent"
	scaffold_devcontainer_user_json_if_missing "$repo_root"
	scaffold_devcontainer_user_policy_override_if_missing "$repo_root"
	scaffold_devcontainer_user_compose_override_if_missing "$repo_root" "$agent" "$ide"

	proxy_image_pinned=$(pull_and_pin_image "${AGENTBOX_PROXY_IMAGE:-$default_proxy_image}")
	agent_image_pinned=$(pull_and_pin_image "${AGENTBOX_AGENT_IMAGE:-$default_agent_image}")

	render_devcontainer_json "$repo_root" "$agent" "$(devcontainer_json_file "$repo_root")"
	write_devcontainer_compose_file \
		"$repo_root" \
		"$agent" \
		"$ide" \
		"$project_name" \
		"$proxy_image_pinned" \
		"$agent_image_pinned"
	write_devcontainer_policy_override_file "$(devcontainer_policy_override_file "$repo_root")" "$ide"
}

ensure_devcontainer_runtime_files() {
	local repo_root=$1
	local agent=$2
	local ide=""
	local project_name=""
	local current_agent=""
	local compose_file
	local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	local default_agent_image
	local proxy_image
	local agent_image=""

	validate_agent "$agent" >/dev/null

	ide="$(read_devcontainer_ide "$repo_root" 2>/dev/null)" || true
	project_name="$(read_devcontainer_project_name "$repo_root" 2>/dev/null)" || true
	current_agent="$(read_active_agent "$repo_root" 2>/dev/null)" || true

	if [[ -z "$ide" ]]
	then
		echo "Devcontainer IDE metadata missing. Defaulting to 'none' for managed file sync." | warning
		ide="none"
	fi

	if [[ -z "$project_name" ]]
	then
		echo "Devcontainer project name metadata missing. Falling back to the default derived name." | warning
		project_name="$(derive_project_name "$repo_root" "devcontainer")"
	fi

	default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"
	compose_file="$(devcontainer_compose_file "$repo_root")"

	proxy_image="$(read_compose_service_image_if_exists "$compose_file" "proxy" 2>/dev/null)" || true
	if [[ -z "$proxy_image" ]]
	then
		proxy_image="$default_proxy_image"
	fi

	if [[ -n "$current_agent" ]] && [[ "$current_agent" == "$agent" ]]
	then
		agent_image="$(read_compose_service_image_if_exists "$compose_file" "agent" 2>/dev/null)" || true
	fi
	if [[ -z "$agent_image" ]]
	then
		agent_image="$default_agent_image"
	fi

	scaffold_cli_shared_policy_if_missing "$repo_root"
	ensure_cli_policy_file "$repo_root" "$agent"
	scaffold_devcontainer_user_json_if_missing "$repo_root"
	scaffold_devcontainer_user_policy_override_if_missing "$repo_root"
	scaffold_devcontainer_user_compose_override_if_missing "$repo_root" "$agent" "$ide"

	render_devcontainer_json "$repo_root" "$agent" "$(devcontainer_json_file "$repo_root")"
	write_devcontainer_compose_file \
		"$repo_root" \
		"$agent" \
		"$ide" \
		"$project_name" \
		"$proxy_image" \
		"$agent_image"
	write_devcontainer_policy_override_file "$(devcontainer_policy_override_file "$repo_root")" "$ide"
	write_devcontainer_state "$repo_root" "$agent" "$ide" "$project_name"
}
