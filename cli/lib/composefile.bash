#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"
# shellcheck source=select.bash
source "$AGB_LIBDIR/select.bash"
# shellcheck source=path.bash
source "$AGB_LIBDIR/path.bash"
# shellcheck source=constants.bash
source "$AGB_LIBDIR/constants.bash"

# Customizes a Docker Compose file with policy and optional user configurations.
# Prompts the user for configuration options unless provided via environment variables:
#   - proxy_image: Docker image for proxy service (pulls and pins to digest)
#   - agent_image: Docker image for agent service (pulls and pins to digest)
#   - mount_claude_config: "true" to mount host Claude config (~/.claude)
#   - enable_shell_customizations: "true" to enable shell customizations
#   - enable_dotfiles: "true" to mount dotfiles
#   - mount_git_readonly: "true" to mount .git directory as read-only
#   - mount_idea_readonly: "true" to mount .idea directory as read-only
#   - mount_vscode_readonly: "true" to mount .vscode directory as read-only
# Args:
#   $1 - Path to the policy file to mount, relative to the Docker Compose file directory
#   $2 - Path to the Docker Compose file to modify
#   $3 - The agent name (e.g., "claude")
#   $4 - The IDE name (e.g., "vscode", "jetbrains", "none") (optional)
#
customize_compose_file() {
	local policy_file=$1
	local compose_file=$2
	local agent=$3
	local ide=${4:-none}

	require yq

	local default_proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	local default_agent_image="ghcr.io/mattolson/agent-sandbox-$agent:latest"

	local compose_dir
	compose_dir=$(dirname "$compose_file")

	verify_relative_path "$compose_dir" "$policy_file"

	# Collect all user input at the top
	: "${proxy_image:=$(read_line "Proxy image [$default_proxy_image]:")}"
	: "${agent_image:=$(read_line "Agent image [$default_agent_image]:")}"

	if [[ $agent == "claude" ]]
	then
		: "${mount_claude_config:=$(select_yes_no "Mount host Claude config (~/.claude)?")}"
	fi

	: "${enable_shell_customizations:=$(select_yes_no "Enable shell customizations?")}"
	: "${enable_dotfiles:=$(select_yes_no "Enable dotfiles?")}"
	: "${mount_git_readonly:=$(select_yes_no "Mount .git/ directory as read-only?")}"

	if [[ $ide == "jetbrains" ]]
	then
		: "${mount_idea_readonly:=$(select_yes_no "Mount .idea/ directory as read-only?")}"
	fi

	if [[ $ide == "vscode" ]]
	then
		: "${mount_vscode_readonly:=$(select_yes_no "Mount .vscode/ directory as read-only?")}"
	fi

	local proxy_image_pinned
	proxy_image_pinned=$(pull_and_pin_image "${proxy_image:-$default_proxy_image}")
	set_proxy_image "$compose_file" "$proxy_image_pinned"

	local agent_image_pinned
	agent_image_pinned=$(pull_and_pin_image "${agent_image:-$default_agent_image}")
	set_agent_image "$compose_file" "$agent_image_pinned"

	add_policy_volume "$compose_file" "$policy_file"

	if [[ $agent == "claude" ]]
	then
		add_claude_config_volumes "$compose_file" "$mount_claude_config"
	fi

	add_shell_customizations_volume "$compose_file" "$enable_shell_customizations"
	add_dotfiles_volume "$compose_file" "$enable_dotfiles"
	add_git_readonly_volume "$compose_file" "$mount_git_readonly"
	add_idea_readonly_volume "$compose_file" "${mount_idea_readonly:-false}"
	add_vscode_readonly_volume "$compose_file" "${mount_vscode_readonly:-false}"

	if [[ $ide == "jetbrains" ]]
	then
		add_jetbrains_capabilities "$compose_file"
	fi

	# Remove blank lines between volume entries/comments.
	# yq inserts blank lines between foot comments and the next sibling;
	# this strips any blank line that sits between two indented lines.
	# Uses D to delete only the blank line, keeping the appended line.
	sed '/^$/{ N; /^\n[[:space:]]/{ s/^\n//; }; }' "$compose_file" > "$compose_file.tmp" && mv "$compose_file.tmp" "$compose_file"
}

# Sets the proxy service image in a Docker Compose file.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Image reference (can be tag or digest)
set_proxy_image() {
	require yq
	local compose_file=$1
	local image=$2

	image="$image" yq -i '.services.proxy.image = env(image)' "$compose_file"
}

# Sets the agent service image in a Docker Compose file.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Image reference (can be tag or digest)
set_agent_image() {
	require yq
	local compose_file=$1
	local image=$2

	image="$image" yq -i '.services.agent.image = env(image)' "$compose_file"
}

# Sets the project name in a Docker Compose file.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Project name
set_project_name() {
	require yq
	local compose_file=$1
	local project_name=$2

	project_name="$project_name" yq -i '. = {"name": env(project_name)} * .' "$compose_file"
}

# Adds policy volume mount to the proxy service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Path to the policy file (relative to compose file)
add_policy_volume() {
	require yq
	local compose_file=$1
	local policy_file=$2

	policy_file="$policy_file" yq -i \
		'.services.proxy.volumes += [env(policy_file) + ":/etc/mitmproxy/policy.yaml:ro"]' "$compose_file"
}

# Adds a foot comment to the last item in a YAML array.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - YAML path to the array (e.g., ".services.agent.volumes")
#   $3 - Comment text to add
add_foot_comment() {
	require yq
	local compose_file=$1
	local array_path=$2
	local comment=$3

	local item_count
	item_count=$(yq "$array_path | length" "$compose_file")

	if [[ $item_count -eq 0 ]]
	then
		echo "${FUNCNAME[0]}: Cannot add foot comment to empty array at $array_path" >&2
		return 1
	fi

	array_path="$array_path" comment="$comment" yq -i '
			(eval(env(array_path)) | .[-1]) foot_comment = (
				((eval(env(array_path)) | .[-1] | foot_comment) // "") + "\n" + strenv(comment) | sub("^\n", "")
			)' "$compose_file"
}

# Adds a foot comment to the last volume entry in the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Comment text to add
add_volume_foot_comment() {
	local compose_file=$1
	local comment=$2

	add_foot_comment "$compose_file" ".services.agent.volumes" "$comment"
}

# Adds a volume entry to the agent service, either as active or commented.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Volume entry (e.g., "../.git:/workspace/.git:ro")
#   $3 - true to add as active entry, false to add as comment
#   $4 - Optional description comment
add_volume_entry() {
	require yq
	local compose_file=$1
	local volume_entry=$2
	local active=$3
	local comment=${4:-}

	if [[ $active == "true" ]]
	then
		volume_entry="$volume_entry" yq -i \
			'.services.agent.volumes += [env(volume_entry)]' "$compose_file"
		if [[ -n $comment ]]
		then
			comment="$comment" yq -i \
				'(.services.agent.volumes | .[-1]) head_comment = strenv(comment)' "$compose_file"
		fi
	else
		if [[ -n $comment ]]
		then
			add_volume_foot_comment "$compose_file" "$comment"$'\n'"- $volume_entry"
		else
			add_volume_foot_comment "$compose_file" "- $volume_entry"
		fi
	fi
}

# Adds Claude config volume mounts to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_claude_config_volumes() {
	local compose_file=$1
	local active=${2:-true}

	# shellcheck disable=SC2016
	add_volume_entry "$compose_file" '${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro' "$active" 'Host Claude config (optional)'
	# shellcheck disable=SC2016
	add_volume_entry "$compose_file" '${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro' "$active"
}

# Adds shell customizations volume mount to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_shell_customizations_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_entry "$compose_file" "$AGB_HOME_PATTERN/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro" "$active" 'Shell customizations (optional - scripts sourced at shell startup)'
}

# Adds dotfiles volume mount to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_dotfiles_volume() {
	local compose_file=$1
	local active=${2:-true}

	# shellcheck disable=SC2016
	add_volume_entry "$compose_file" '${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro' "$active" 'Dotfiles (optional - auto-linked into $HOME at startup)'
}

# Adds .git directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_git_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_entry "$compose_file" '../.git:/workspace/.git:ro' "$active" 'Read-only Git directory'
}

# Adds .idea directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_idea_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_entry "$compose_file" '../.idea:/workspace/.idea:ro' "$active" 'Read-only IntelliJ IDEA project directory'
}

# Adds .vscode directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_vscode_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_entry "$compose_file" '../.vscode:/workspace/.vscode:ro' "$active" 'Read-only VS Code project directory'
}

# Adds JetBrains-specific capabilities to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_jetbrains_capabilities() {
	require yq
	local compose_file=$1

	yq -i '.services.agent.cap_add += ["DAC_OVERRIDE", "CHOWN", "FOWNER"]' "$compose_file"
	yq -i '(.services.agent.cap_add[] | select(. == "DAC_OVERRIDE")) head_comment = "following is required by JetBrains devcontainer"' "$compose_file"
}

# Pulls an image and returns its digest.
# Args:
#   $1 - Image reference (can be tag or digest)
pull_and_pin_image() {
	local image=$1

	if [[ $image == *:local ]] || [[ $image != */* ]]
	then
		echo "$image"
		return 0
	fi

	require docker

	# Pull remote image
	docker pull "$image" >&2

	# Get the digest
	local digest
	digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image")

	echo "$digest"
}
