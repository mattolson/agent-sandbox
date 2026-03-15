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

devcontainer_json_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/devcontainer.json"
}

devcontainer_user_json_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/devcontainer.user.json"
}

devcontainer_managed_policy_file() {
	local repo_root="${1:-}"

	echo "$(cli_policy_dir "$repo_root")/policy.devcontainer.yaml"
}

devcontainer_policy_override_file() {
	local repo_root="${1:-}"

	echo "$(devcontainer_dir "$repo_root")/policy.override.yaml"
}

devcontainer_centralized_runtime_initialized() {
	local repo_root="${1:-}"

	[[ -f "$(cli_devcontainer_mode_compose_file "$repo_root")" ]]
}

emit_devcontainer_compose_files() {
	local repo_root="${1:-}"
	local active_agent=""
	local base_file
	local agent_file
	local mode_file
	local shared_override
	local agent_override

	active_agent="$(read_active_agent "$repo_root")" || {
		echo "Active agent state missing for centralized devcontainer layout at $repo_root. Run 'agentbox switch --agent <name>'." | error
		return 1
	}

	base_file="$(cli_base_compose_file "$repo_root")"
	agent_file="$(cli_agent_compose_file "$repo_root" "$active_agent")"
	mode_file="$(cli_devcontainer_mode_compose_file "$repo_root")"
	shared_override="$(cli_user_override_file "$repo_root")"
	agent_override="$(cli_user_agent_override_file "$repo_root" "$active_agent")"

	if [[ ! -f "$base_file" ]]
	then
		echo "Devcontainer compose base file not found: $base_file" | error
		return 1
	fi

	if [[ ! -f "$agent_file" ]]
	then
		echo "Devcontainer compose agent file not found for '$active_agent': $agent_file" | error
		return 1
	fi

	if [[ ! -f "$mode_file" ]]
	then
		echo "Devcontainer compose mode overlay not found: $mode_file" | error
		return 1
	fi

	printf '%s\n' "$base_file"
	printf '%s\n' "$agent_file"
	printf '%s\n' "$mode_file"

	if [[ -f "$shared_override" ]]
	then
		printf '%s\n' "$shared_override"
	fi

	if [[ -f "$agent_override" ]]
	then
		printf '%s\n' "$agent_override"
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

cleanup_legacy_devcontainer_managed_files() {
	local repo_root=$1
	local legacy_compose_file
	local legacy_policy_file

	legacy_compose_file="$(devcontainer_dir "$repo_root")/docker-compose.base.yml"
	legacy_policy_file="$(devcontainer_policy_override_file "$repo_root")"

	if [[ -f "$legacy_compose_file" ]]
	then
		rm -f "$legacy_compose_file"
	fi

	if [[ -f "$legacy_policy_file" ]]
	then
		rm -f "$legacy_policy_file"
	fi
}

set_devcontainer_override_defaults_for_ide() {
	local ide=$1

	validate_devcontainer_ide "$ide" >/dev/null

	: "${AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS:=false}"
	: "${AGENTBOX_ENABLE_DOTFILES:=false}"
	: "${AGENTBOX_MOUNT_GIT_READONLY:=false}"
	AGENTBOX_MOUNT_IDEA_READONLY=false
	AGENTBOX_MOUNT_VSCODE_READONLY=false
}

devcontainer_template_json_file() {
	local agent=$1

	validate_agent "$agent" >/dev/null
	echo "$AGB_TEMPLATEDIR/$agent/devcontainer/devcontainer.json"
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

	replace_file_if_changed "$tmp_file" "$output_file"
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

write_devcontainer_policy_file() {
	local policy_file=$1
	local ide=$2
	local services=""
	local tmp_file

	validate_devcontainer_ide "$ide" >/dev/null
	require yq

	tmp_file="${policy_file}.tmp"
	copy_policy_template "$tmp_file" "policy.devcontainer.yaml"

	if [[ "$ide" != "none" ]]
	then
		services="$ide"
	fi

	services="$services" yq -i \
		'.services = ((strenv(services) | split("\n")) | map(select(. != "")))' \
		"$tmp_file"
	replace_file_if_changed "$tmp_file" "$policy_file"
}

write_devcontainer_mode_compose_file() {
	local repo_root=$1
	local ide=$2
	local project_name=$3
	local compose_file
	local tmp_file

	validate_devcontainer_ide "$ide" >/dev/null

	compose_file="$(cli_devcontainer_mode_compose_file "$repo_root")"
	tmp_file="${compose_file}.tmp"

	mkdir -p "$(dirname "$compose_file")"
	cp "$AGB_TEMPLATEDIR/compose/mode.devcontainer.yml" "$tmp_file"
	set_project_name "$tmp_file" "$(apply_mode_suffix "$project_name" "devcontainer")"

	if [[ "$ide" == "jetbrains" ]]
	then
		add_volume_entry "$tmp_file" '../../.idea:/workspace/.idea:ro' "true"
		add_jetbrains_capabilities "$tmp_file"
	elif [[ "$ide" == "vscode" ]]
	then
		add_volume_entry "$tmp_file" '../../.vscode:/workspace/.vscode:ro' "true"
	fi

	replace_file_if_changed "$tmp_file" "$compose_file"
}

initialize_devcontainer_layout() {
	local repo_root=$1
	local agent=$2
	local ide=$3
	local project_name=$4

	validate_agent "$agent" >/dev/null
	validate_devcontainer_ide "$ide" >/dev/null

	set_devcontainer_override_defaults_for_ide "$ide"
	initialize_cli_layered_layout "$repo_root" "$agent" "$project_name"
	scaffold_devcontainer_user_json_if_missing "$repo_root"

	render_devcontainer_json "$repo_root" "$agent" "$(devcontainer_json_file "$repo_root")"
	write_devcontainer_mode_compose_file "$repo_root" "$ide" "$project_name"
	write_devcontainer_policy_file "$(devcontainer_managed_policy_file "$repo_root")" "$ide"
	cleanup_legacy_devcontainer_managed_files "$repo_root"
}

ensure_devcontainer_runtime_files() {
	local repo_root=$1
	local agent=$2
	local ide=""
	local project_name=""
	local base_compose_file
	local agent_compose_file
	local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	local default_agent_image
	local proxy_image
	local agent_image=""

	validate_agent "$agent" >/dev/null

	base_compose_file="$(cli_base_compose_file "$repo_root")"
	agent_compose_file="$(cli_agent_compose_file "$repo_root" "$agent")"

	ide="$(read_devcontainer_ide "$repo_root" 2>/dev/null)" || true
	project_name="$(read_project_name "$repo_root" 2>/dev/null)" || true

	if [[ -z "$ide" ]]
	then
		echo "Devcontainer IDE metadata missing. Defaulting to 'none' for managed file sync." | warning
		ide="none"
	fi

	if [[ -z "$project_name" ]]
	then
		project_name="$(read_project_name_if_exists "$base_compose_file" 2>/dev/null)" || true
	fi

	if [[ -n "$project_name" ]]
	then
		project_name="$(strip_mode_suffix "$project_name" "devcontainer")"
	fi

	if [[ -z "$project_name" ]]
	then
		echo "Project name metadata missing. Falling back to the default derived name." | warning
		project_name="$(derive_base_project_name "$repo_root")"
	fi

	default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"

	proxy_image="$(read_compose_service_image_if_exists "$base_compose_file" "proxy" 2>/dev/null)" || true
	if [[ -z "$proxy_image" ]]
	then
		proxy_image="$default_proxy_image"
	fi

	if [[ -f "$agent_compose_file" ]]
	then
		agent_image="$(read_compose_service_image_if_exists "$agent_compose_file" "agent" 2>/dev/null)" || true
	fi
	if [[ -z "$agent_image" ]]
	then
		agent_image="$default_agent_image"
	fi

	set_devcontainer_override_defaults_for_ide "$ide"

	if [[ ! -f "$base_compose_file" ]]
	then
		write_cli_base_compose_file "$repo_root" "$project_name" "$proxy_image"
	fi
	set_project_name "$base_compose_file" "$project_name"

	if [[ ! -f "$agent_compose_file" ]]
	then
		write_cli_agent_compose_file "$repo_root" "$agent" "$agent_image"
	fi

	ensure_cli_agent_runtime_files "$repo_root" "$agent"
	scaffold_devcontainer_user_json_if_missing "$repo_root"

	render_devcontainer_json "$repo_root" "$agent" "$(devcontainer_json_file "$repo_root")"
	write_devcontainer_mode_compose_file "$repo_root" "$ide" "$project_name"
	write_devcontainer_policy_file "$(devcontainer_managed_policy_file "$repo_root")" "$ide"
	cleanup_legacy_devcontainer_managed_files "$repo_root"
	write_devcontainer_state "$repo_root" "$agent" "$ide" "$project_name"
}
