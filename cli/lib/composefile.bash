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

	: "${proxy_image:=$(read_line "Proxy image [$default_proxy_image]:")}"

	local proxy_image_pinned
	proxy_image_pinned=$(pull_and_pin_image "${proxy_image:-$default_proxy_image}")
	set_proxy_image "$compose_file" "$proxy_image_pinned"

	: "${agent_image:=$(read_line "Agent image [$default_agent_image]:")}"

	local agent_image_pinned
	agent_image_pinned=$(pull_and_pin_image "${agent_image:-$default_agent_image}")
	set_agent_image "$compose_file" "$agent_image_pinned"

	add_policy_volume "$compose_file" "$policy_file"

	if [[ $agent == "claude" ]]
	then
		: "${mount_claude_config:=$(select_yes_no "Mount host Claude config (~/.claude)?")}"
		if [[ $mount_claude_config == "true" ]]
		then
			add_claude_config_volumes "$compose_file"
		fi
	fi

	: "${enable_shell_customizations:=$(select_yes_no "Enable shell customizations?")}"
	if [[ $enable_shell_customizations == "true" ]]
	then
		add_shell_customizations_volume "$compose_file"

		: "${enable_dotfiles:=$(select_yes_no "Enable dotfiles?")}"
		if [[ $enable_dotfiles == "true" ]]
		then
			add_dotfiles_volume "$compose_file"
		fi
	fi

	: "${mount_git_readonly:=$(select_yes_no "Mount .git/ directory as read-only?")}"
	if [[ $mount_git_readonly == "true" ]]
	then
		add_git_readonly_volume "$compose_file"
	fi

	: "${mount_idea_readonly:=$(select_yes_no "Mount .idea/ directory as read-only?")}"
	if [[ $mount_idea_readonly == "true" ]]
	then
		add_idea_readonly_volume "$compose_file"
	fi

	: "${mount_vscode_readonly:=$(select_yes_no "Mount .vscode/ directory as read-only?")}"
	if [[ $mount_vscode_readonly == "true" ]]
	then
		add_vscode_readonly_volume "$compose_file"
	fi
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

# Adds Claude config volume mounts to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_claude_config_volumes() {
	require yq
	local compose_file=$1

	# shellcheck disable=SC2016
	yq -i \
		'.services.agent.volumes += [
			"${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro",
			"${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro"
		]' "$compose_file"
}

# Adds shell customizations volume mount to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_shell_customizations_volume() {
	require yq
	local compose_file=$1

	yq -i \
		'.services.agent.volumes += [
			env(AGB_HOME_PATTERN) + "/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro"
		]' "$compose_file"
}

# Adds dotfiles volume mount to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_dotfiles_volume() {
	require yq
	local compose_file=$1

	# shellcheck disable=SC2016
	yq -i \
		'.services.agent.volumes += [
			"${HOME}/.dotfiles:/home/dev/.dotfiles:ro"
		]' "$compose_file"
}

# Adds .git directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_git_readonly_volume() {
	require yq
	local compose_file=$1

	yq -i \
		'.services.agent.volumes += [
			"../.git:/workspace/.git:ro"
		]' "$compose_file"
}

# Adds .idea directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_idea_readonly_volume() {
	require yq
	local compose_file=$1

	yq -i \
		'.services.agent.volumes += [
			"../.idea:/workspace/.idea:ro"
		]' "$compose_file"
}

# Adds .vscode directory mount as read-only to the agent service.
# Args:
#   $1 - Path to the Docker Compose file
add_vscode_readonly_volume() {
	require yq
	local compose_file=$1

	yq -i \
		'.services.agent.volumes += [
			"../.vscode:/workspace/.vscode:ro"
		]' "$compose_file"
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
