#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"
# shellcheck source=select.bash
source "$AGB_LIBDIR/select.bash"
# shellcheck source=path.bash
source "$AGB_LIBDIR/path.bash"

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
#   $1 - The agent name (e.g., "claude")
#   $2 - Path to the policy file to mount, relative to the Docker Compose file directory
#   $3 - Path to the Docker Compose file to modify
#
customize_compose_file() {
	local agent=$1
	local policy_file=$2
	local compose_file=$3

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
	: "${mount_idea_readonly:=$(select_yes_no "Mount .idea/ directory as read-only?")}"
	: "${mount_vscode_readonly:=$(select_yes_no "Mount .vscode/ directory as read-only?")}"

	# Apply configuration based on collected input
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
	add_idea_readonly_volume "$compose_file" "$mount_idea_readonly"
	add_vscode_readonly_volume "$compose_file" "$mount_vscode_readonly"
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

# Adds a foot comment to the last volume entry in the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Comment text to add
add_volume_foot_comment() {
	require yq
	local compose_file=$1
	local comment=$2

	local volume_count
	volume_count=$(yq '.services.agent.volumes | length' "$compose_file")

	if [[ $volume_count -eq 0 ]]
	then
		echo "${FUNCNAME[0]}: Cannot add foot comment to empty volumes array" >&2
		return 1
	fi

	comment="$comment" yq -i '
			.services.agent.volumes[-1] foot_comment = (
				((.services.agent.volumes[-1] | foot_comment) // "") + "\n" + strenv(comment) | sub("^\n", "")
			)
		' "$compose_file"
}

# Adds a volume entry to the agent service, either as active or commented.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - Volume entry (e.g., "../.git:/workspace/.git:ro")
#   $3 - true to add as active entry, false to add as comment
add_volume_entry() {
	require yq
	local compose_file=$1
	local volume_entry=$2
	local active=$3

	if [[ $active == "true" ]]
	then
		volume_entry="$volume_entry" yq -i \
			'.services.agent.volumes += [env(volume_entry)]' "$compose_file"
	else
		add_volume_foot_comment "$compose_file" "- $volume_entry"
	fi
}

# Adds Claude config volume mounts to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_claude_config_volumes() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_foot_comment "$compose_file" 'Host Claude config (optional)'

	# shellcheck disable=SC2016
	add_volume_entry "$compose_file" '${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro' "$active"
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

	add_volume_foot_comment "$compose_file" 'Shell customizations (optional - scripts sourced at shell startup)'

	add_volume_entry "$compose_file" "$AGB_HOME_PATTERN/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro" "$active"
}

# Adds dotfiles volume mount to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_dotfiles_volume() {
	local compose_file=$1
	local active=${2:-true}

	# shellcheck disable=SC2016
	add_volume_foot_comment "$compose_file" 'Dotfiles (optional - auto-linked into $HOME at startup)'

	# shellcheck disable=SC2016
	add_volume_entry "$compose_file" '${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro' "$active"
}

# Adds .git directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_git_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_foot_comment "$compose_file" 'Read-only Git directory'

	add_volume_entry "$compose_file" '../.git:/workspace/.git:ro' "$active"
}

# Adds .idea directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_idea_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_foot_comment "$compose_file" 'Read-only IntelliJ IDEA project directory'

	add_volume_entry "$compose_file" '../.idea:/workspace/.idea:ro' "$active"
}

# Adds .vscode directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
#   $2 - true to add as active, false to add as comment
add_vscode_readonly_volume() {
	local compose_file=$1
	local active=${2:-true}

	add_volume_foot_comment "$compose_file" 'Read-only VS Code project directory'

	add_volume_entry "$compose_file" '../.vscode:/workspace/.vscode:ro' "$active"
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
