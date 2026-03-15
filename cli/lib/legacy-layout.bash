#!/usr/bin/env bash

# shellcheck source=compat.bash
source "$AGB_LIBDIR/compat.bash"
# shellcheck source=agent.bash
source "$AGB_LIBDIR/agent.bash"
# shellcheck source=cli-compose.bash
source "$AGB_LIBDIR/cli-compose.bash"
# shellcheck source=constants.bash
source "$AGB_LIBDIR/constants.bash"
# shellcheck source=devcontainer.bash
source "$AGB_LIBDIR/devcontainer.bash"

legacy_upgrade_guide_path() {
	echo "docs/upgrades/m8-layered-layout.md"
}

legacy_cli_compose_file() {
	local repo_root=$1

	echo "$repo_root/$AGB_PROJECT_DIR/docker-compose.yml"
}

legacy_devcontainer_compose_file() {
	local repo_root=$1

	echo "$repo_root/.devcontainer/docker-compose.yml"
}

legacy_devcontainer_policy_file() {
	local repo_root=$1
	local agent=$2

	validate_agent "$agent" >/dev/null
	echo "$repo_root/$AGB_PROJECT_DIR/policy-devcontainer-$agent.yaml"
}

unsupported_legacy_layout_files() {
	local repo_root=$1
	local file=""
	local agent=""
	local -a files=()

	file="$(legacy_cli_compose_file "$repo_root")"
	if [[ -f "$file" ]]
	then
		files+=("$file")
	fi

	file="$(legacy_devcontainer_compose_file "$repo_root")"
	if [[ -f "$file" ]]
	then
		files+=("$file")
	fi

	while IFS= read -r agent
	do
		file="$(legacy_devcontainer_policy_file "$repo_root" "$agent")"
		if [[ -f "$file" ]]
		then
			files+=("$file")
		fi

		file="$(cli_legacy_policy_file "$repo_root" "$agent")"
		if [[ -f "$file" ]]
		then
			files+=("$file")
		fi
	done < <(supported_agents)

	if [[ ${#files[@]} -gt 0 ]]
	then
		printf '%s\n' "${files[@]}"
	fi
}

legacy_layout_rename_path() {
	local file=$1
	local directory=""
	local basename=""
	local stem=""
	local extension=""

	directory="$(dirname -- "$file")"
	basename="$(basename -- "$file")"
	stem="$basename"

	case "$basename" in
	*.yaml)
		stem="${basename%.yaml}"
		extension=".yaml"
		;;
	*.yml)
		stem="${basename%.yml}"
		extension=".yml"
		;;
	*.json)
		stem="${basename%.json}"
		extension=".json"
		;;
	esac

	printf '%s/%s.legacy%s\n' "$directory" "$stem" "$extension"
}

legacy_layout_relative_path() {
	local repo_root=$1
	local file=$2

	if [[ "$file" == "$repo_root"/* ]]
	then
		printf '%s\n' "${file#"$repo_root"/}"
	else
		printf '%s\n' "$file"
	fi
}

legacy_layout_file_mode() {
	local repo_root=$1
	local file=$2
	local relative=""

	relative="$(legacy_layout_relative_path "$repo_root" "$file")"

	case "$relative" in
	"$AGB_PROJECT_DIR"/docker-compose.yml | "$AGB_PROJECT_DIR"/policy-cli-*.yaml)
		echo "cli"
		;;
	.devcontainer/docker-compose.yml | "$AGB_PROJECT_DIR"/policy-devcontainer-*.yaml)
		echo "devcontainer"
		;;
	esac
}

infer_legacy_layout_mode() {
	local repo_root=$1
	local preferred_mode="${2:-}"
	local file=""
	local file_mode=""
	local resolved_mode=""

	if [[ -n "$preferred_mode" ]]
	then
		printf '%s\n' "$preferred_mode"
		return 0
	fi

	while IFS= read -r file
	do
		file_mode="$(legacy_layout_file_mode "$repo_root" "$file")"
		if [[ -z "$file_mode" ]]
		then
			continue
		fi

		if [[ -z "$resolved_mode" ]]
		then
			resolved_mode="$file_mode"
			continue
		fi

		if [[ "$resolved_mode" != "$file_mode" ]]
		then
			return 0
		fi
	done < <(unsupported_legacy_layout_files "$repo_root")

	if [[ -n "$resolved_mode" ]]
	then
		printf '%s\n' "$resolved_mode"
	fi
}

legacy_layout_file_agent() {
	local file=$1
	local basename=""

	basename="$(basename -- "$file")"
	case "$basename" in
	policy-cli-*.yaml)
		printf '%s\n' "${basename#policy-cli-}"
		;;
	policy-devcontainer-*.yaml)
		printf '%s\n' "${basename#policy-devcontainer-}"
		;;
	*)
		return 0
		;;
	esac
}

infer_legacy_layout_agent() {
	local repo_root=$1
	local preferred_agent="${2:-}"
	local file=""
	local basename=""
	local agent=""
	local resolved_agent=""

	if [[ -n "$preferred_agent" ]]
	then
		printf '%s\n' "$preferred_agent"
		return 0
	fi

	while IFS= read -r file
	do
		basename="$(legacy_layout_file_agent "$file")"
		case "$basename" in
		*.yaml)
			agent="${basename%.yaml}"
			;;
		"")
			continue
			;;
		esac

		if [[ -z "$resolved_agent" ]]
		then
			resolved_agent="$agent"
			continue
		fi

		if [[ "$resolved_agent" != "$agent" ]]
		then
			return 0
		fi
	done < <(unsupported_legacy_layout_files "$repo_root")

	if [[ -n "$resolved_agent" ]]
	then
		printf '%s\n' "$resolved_agent"
	fi
}

print_legacy_layout_error() {
	local repo_root=$1
	local command_name=$2
	local preferred_agent="${3:-}"
	local preferred_mode="${4:-}"
	local preferred_ide="${5:-}"
	local guide_path=""
	local resolved_agent=""
	local resolved_mode=""
	local init_command=""
	local file=""
	local relative=""
	local renamed=""
	local agent_label="<agent>"
	local -a files=()

	mapfile -t files < <(unsupported_legacy_layout_files "$repo_root")
	if [[ ${#files[@]} -eq 0 ]]
	then
		return 1
	fi

	guide_path="$(legacy_upgrade_guide_path)"
	resolved_agent="$(infer_legacy_layout_agent "$repo_root" "$preferred_agent")"
	resolved_mode="$(infer_legacy_layout_mode "$repo_root" "$preferred_mode")"

	if [[ -n "$resolved_agent" ]]
	then
		agent_label="$resolved_agent"
	fi

	init_command="agentbox init"
	if [[ -n "$resolved_agent" ]]
	then
		init_command="$init_command --agent $resolved_agent"
	else
		init_command="$init_command --agent <agent>"
	fi

	case "$resolved_mode" in
	cli)
		init_command="$init_command --mode cli"
		;;
	devcontainer)
		init_command="$init_command --mode devcontainer"
		if [[ -n "$preferred_ide" ]]
		then
			init_command="$init_command --ide $preferred_ide"
		else
			init_command="$init_command --ide <vscode|jetbrains|none>"
		fi
		;;
	*)
		init_command="$init_command --mode <cli|devcontainer>"
		;;
	esac

	{
		printf 'agentbox %s does not support the legacy single-file layout.\n\n' "$command_name"
		echo "Found legacy generated files:"
		for file in "${files[@]}"
		do
			relative="$(legacy_layout_relative_path "$repo_root" "$file")"
			printf -- '- %s\n' "$relative"
		done

		echo
		echo "To upgrade safely:"
		echo "1. Rename the legacy generated files so agentbox no longer treats them as live config:"
		for file in "${files[@]}"
		do
			relative="$(legacy_layout_relative_path "$repo_root" "$file")"
			renamed="$(legacy_layout_relative_path "$repo_root" "$(legacy_layout_rename_path "$file")")"
			printf '   %s -> %s\n' "$relative" "$renamed"
		done
		echo "2. Re-run:"
		printf '   %s\n' "$init_command"
		echo "3. Copy your customizations into the new user-owned files:"
		echo "   .agent-sandbox/compose/user.override.yml"
		printf '   .agent-sandbox/compose/user.agent.%s.override.yml\n' "$agent_label"
		echo "   .agent-sandbox/policy/user.policy.yaml"
		printf '   .agent-sandbox/policy/user.agent.%s.policy.yaml\n' "$agent_label"

		if [[ "$resolved_mode" == "devcontainer" ]] || [[ -f "$(legacy_devcontainer_compose_file "$repo_root")" ]]
		then
			echo "   .devcontainer/devcontainer.user.json"
		fi

		echo
		echo "Do not copy customizations back into managed files under .agent-sandbox/compose/."
		printf 'See %s for the full upgrade guide.\n' "$guide_path"
	} >&2
}

abort_if_unsupported_legacy_layout() {
	local repo_root=$1
	local command_name=$2
	local preferred_agent="${3:-}"
	local preferred_mode="${4:-}"
	local preferred_ide="${5:-}"
	local -a files=()

	mapfile -t files < <(unsupported_legacy_layout_files "$repo_root")
	if [[ ${#files[@]} -eq 0 ]]
	then
		return 0
	fi

	print_legacy_layout_error "$repo_root" "$command_name" "$preferred_agent" "$preferred_mode" "$preferred_ide"
	return 1
}
