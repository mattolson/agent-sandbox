#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# This is a regression test verifying that compose configuration is generated correctly.

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/cli
	source "$AGB_LIBEXECDIR/init/cli"
	# shellcheck source=../../libexec/init/devcontainer
	source "$AGB_LIBEXECDIR/init/devcontainer"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR/$AGB_PROJECT_DIR"
}

teardown() {
	unstub_all
}

assert_proxy_service() {
	local compose_file=$1
	local expected_image=$2

	run yq '.services.proxy.image' "$compose_file"
	assert_output "$expected_image"

	yq -e '.services.proxy.cap_drop[] | select(. == "ALL")' "$compose_file"

	yq -e '.services.proxy.environment[] | select(. == "PROXY_MODE=enforce")' "$compose_file"
}

assert_devcontainer_agent_service_base() {
	local compose_file=$1
	local expected_image=$2

	run yq '.services.agent.image' "$compose_file"
	assert_output "$expected_image"

	run yq '.services.agent.working_dir' "$compose_file"
	assert_output "/workspace"

	yq -e '.services.agent.cap_drop[] | select(. == "ALL")' "$compose_file"
}

assert_common_environment_vars() {
	local compose_file=$1

	yq -e '.services.agent.environment[] | select(. == "HTTP_PROXY=http://proxy:8080")' "$compose_file"

	yq -e '.services.agent.environment[] | select(. == "HTTPS_PROXY=http://proxy:8080")' "$compose_file"

	yq -e '.services.agent.environment[] | select(. == "NO_PROXY=localhost,127.0.0.1,proxy")' "$compose_file"
}

assert_named_volumes() {
	local compose_file=$1
	shift
	local volume_names=("$@")

	for volume_name in "${volume_names[@]}"
	do
		volume_name="$volume_name" yq -e '.volumes | select(has(env(volume_name)))' "$compose_file"
	done
}

assert_devcontainer_managed_policy_file() {
	local policy_file=$1
	local ide=$2

	assert [ -f "$policy_file" ]
	run yq '.domains | length' "$policy_file"
	assert_output "0"

	case "$ide" in
	vscode | jetbrains)
		run yq '.services | length' "$policy_file"
		assert_output "1"
		yq -e '.services[] | select(. == "'"$ide"'")' "$policy_file"
		;;
	none)
		run yq '.services | length' "$policy_file"
		assert_output "0"
		;;
	esac
}

assert_devcontainer_user_json_file() {
	local json_file=$1

	assert [ -f "$json_file" ]
	run yq 'keys | length' "$json_file"
	assert_output "0"
}

assert_devcontainer_json_file() {
	local json_file=$1
	local agent=$2

	assert [ -f "$json_file" ]
	run yq -r '.dockerComposeFile[0]' "$json_file"
	assert_output "../.agent-sandbox/compose/base.yml"
	run yq -r '.dockerComposeFile[1]' "$json_file"
	assert_output "../.agent-sandbox/compose/agent.$agent.yml"
	run yq -r '.dockerComposeFile[2]' "$json_file"
	assert_output "../.agent-sandbox/compose/mode.devcontainer.yml"
	run yq -r '.dockerComposeFile[3]' "$json_file"
	assert_output "../.agent-sandbox/compose/user.override.yml"
	run yq -r '.dockerComposeFile[4]' "$json_file"
	assert_output "../.agent-sandbox/compose/user.agent.$agent.override.yml"
	run yq -r '.service' "$json_file"
	assert_output "agent"
}

assert_cli_base_layer() {
	local compose_file=$1
	local expected_name=$2
	local expected_image=$3

	assert [ -f "$compose_file" ]

	run yq '.name' "$compose_file"
	assert_output "$expected_name"

	assert_proxy_service "$compose_file" "$expected_image"

	run yq '.services.agent.image' "$compose_file"
	assert_output "null"

	run yq '.services.agent.working_dir' "$compose_file"
	assert_output "/workspace"

	yq -e '.services.agent.cap_drop[] | select(. == "ALL")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "NET_ADMIN")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "NET_RAW")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "SETUID")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "SETGID")' "$compose_file"

	assert_common_environment_vars "$compose_file"

	yq -e '.services.agent.environment[] | select(. == "GODEBUG=http2client=0")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../..:/workspace")' "$compose_file"
	yq -e '.services.agent.volumes[] | select(. == "..:/workspace/.agent-sandbox:ro")' "$compose_file"
	yq -e '.services.agent.volumes[] | select(. == "proxy-ca:/etc/mitmproxy:ro")' "$compose_file"
	yq -e '.services.proxy.volumes[] | select(. == "../policy/user.policy.yaml:/etc/agent-sandbox/policy/user.policy.yaml:ro")' "$compose_file"

	assert_named_volumes "$compose_file" "proxy-state" "proxy-ca"
}

assert_cli_user_policy_file() {
	local policy_file=$1

	assert [ -f "$policy_file" ]
	run yq '.services | length' "$policy_file"
	assert_output "0"
	run yq '.domains | length' "$policy_file"
	assert_output "0"
}

assert_cli_shared_override() {
	local compose_file=$1
	local include_idea="${2:-true}"
	local include_vscode="${3:-true}"

	assert [ -f "$compose_file" ]

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../../.git:/workspace/.git:ro")' "$compose_file"

	if [[ "$include_idea" == "true" ]]
	then
		yq -e '.services.agent.volumes[] | select(. == "../../.idea:/workspace/.idea:ro")' "$compose_file"
	else
		run yq '.services.agent.volumes[] | select(. == "../../.idea:/workspace/.idea:ro")' "$compose_file"
		assert_output ""
	fi

	if [[ "$include_vscode" == "true" ]]
	then
		yq -e '.services.agent.volumes[] | select(. == "../../.vscode:/workspace/.vscode:ro")' "$compose_file"
	else
		run yq '.services.agent.volumes[] | select(. == "../../.vscode:/workspace/.vscode:ro")' "$compose_file"
		assert_output ""
	fi
}

assert_cli_agent_layer_base() {
	local compose_file=$1
	local expected_image=$2
	local agent=$3
	local state_path=$4
	local state_volume=$5
	local history_volume=$6

	assert [ -f "$compose_file" ]

	run yq '.services.agent.image' "$compose_file"
	assert_output "$expected_image"

	yq -e '.services.proxy.volumes[] | select(. == "../policy/user.agent.'"$agent"'.policy.yaml:/etc/agent-sandbox/policy/user.agent.policy.yaml:ro")' "$compose_file"
	yq -e '.services.proxy.environment[] | select(. == "AGENTBOX_ACTIVE_AGENT='"$agent"'")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "'"$state_volume:$state_path"'")' "$compose_file"
	yq -e '.services.agent.volumes[] | select(. == "'"$history_volume"':/commandhistory")' "$compose_file"

	assert_named_volumes "$compose_file" "$state_volume" "$history_volume"
}

assert_claude_cli_layer() {
	local compose_file=$1

	assert_cli_agent_layer_base \
		"$compose_file" \
		"ghcr.io/mattolson/agent-sandbox-claude@sha256:def456" \
		"claude" \
		"/home/dev/.claude" \
		"claude-state" \
		"claude-history"

	yq -e '.services.agent.environment[] | select(. == "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1")' "$compose_file"
}

assert_copilot_cli_layer() {
	local compose_file=$1

	assert_cli_agent_layer_base \
		"$compose_file" \
		"ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789" \
		"copilot" \
		"/home/dev/.copilot" \
		"copilot-state" \
		"copilot-history"
}

assert_codex_cli_layer() {
	local compose_file=$1

	assert_cli_agent_layer_base \
		"$compose_file" \
		"ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012" \
		"codex" \
		"/home/dev/.codex" \
		"codex-state" \
		"codex-history"
}

assert_claude_cli_override() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$compose_file"
}

assert_non_claude_cli_override() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	# shellcheck disable=SC2016
	run yq '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$compose_file"
	assert_output ""
}

assert_devcontainer_mode_overlay() {
	local compose_file=$1
	local ide=$2
	local expected_name=$3

	assert [ -f "$compose_file" ]

	run yq '.name' "$compose_file"
	assert_output "$expected_name"

	yq -e '.services.proxy.volumes[] | select(. == "../policy/policy.devcontainer.yaml:/etc/agent-sandbox/policy/devcontainer.policy.yaml:ro")' "$compose_file"
	yq -e '.services.agent.volumes[] | select(. == "../../.devcontainer:/workspace/.devcontainer:ro")' "$compose_file"

	if [[ "$ide" == "jetbrains" ]]
	then
		yq -e '.services.agent.volumes[] | select(. == "../../.idea:/workspace/.idea:ro")' "$compose_file"
		assert_jetbrains_capabilities "$compose_file"
		run yq '.services.agent.volumes[] | select(. == "../../.vscode:/workspace/.vscode:ro")' "$compose_file"
		assert_output ""
	elif [[ "$ide" == "vscode" ]]
	then
		run yq '.services.agent.volumes[] | select(. == "../../.idea:/workspace/.idea:ro")' "$compose_file"
		assert_output ""
		yq -e '.services.agent.volumes[] | select(. == "../../.vscode:/workspace/.vscode:ro")' "$compose_file"
	else
		run yq '.services.agent.volumes[] | select(. == "../../.idea:/workspace/.idea:ro")' "$compose_file"
		assert_output ""
		run yq '.services.agent.volumes[] | select(. == "../../.vscode:/workspace/.vscode:ro")' "$compose_file"
		assert_output ""
	fi
}

assert_jetbrains_capabilities() {
	local compose_file=$1

	yq -e '.services.agent.cap_add[] | select(. == "DAC_OVERRIDE")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "CHOWN")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "FOWNER")' "$compose_file"
}

claude_agent_compose_file_has_expected_content() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	assert_claude_cli_layer "$compose_file"
	yq -e '.services.agent.environment[] | select(. == "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1")' "$compose_file"
	run yq '.services.agent.environment[] | select(. == "CLAUDE_CONFIG_DIR=/home/dev/.claude")' "$compose_file"
	assert_output ""
}

copilot_agent_compose_file_has_expected_content() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	assert_copilot_cli_layer "$compose_file"
}

codex_agent_compose_file_has_expected_content() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	assert_codex_cli_layer "$compose_file"
	run yq '.services.agent.environment[] | select(. == "CODEX_HOME=/home/dev/.codex")' "$compose_file"
	assert_output ""
}

@test "cli creates layered compose files for claude agent with all options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export AGENTBOX_MOUNT_CLAUDE_CONFIG="true"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run cli \
		--project-path "$PROJECT_DIR" \
		--agent "claude"
	assert_success

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.claude.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml"
	assert_claude_cli_layer "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.claude.yml"
	assert_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.claude.override.yml"
}

@test "devcontainer creates centralized runtime files for claude agent with all options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export AGENTBOX_MOUNT_CLAUDE_CONFIG="true"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run devcontainer \
		--project-path "$PROJECT_DIR" \
		--agent "claude" \
		--ide "jetbrains"
	assert_success

	run yq '.name' "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml"
	assert_output "project-sandbox"

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	claude_agent_compose_file_has_expected_content "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.claude.yml"
	assert_devcontainer_mode_overlay "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml" "jetbrains" "project-sandbox-devcontainer"
	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "claude"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "jetbrains"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.claude.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" "false" "false"
	assert_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.claude.override.yml"
}

@test "cli creates layered compose files for copilot agent with all options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run cli \
		--project-path "$PROJECT_DIR" \
		--agent "copilot"
	assert_success

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.copilot.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml"
	assert_copilot_cli_layer "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.copilot.yml"
	assert_non_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.copilot.override.yml"
}

@test "devcontainer creates centralized runtime files for copilot agent with all options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run devcontainer \
		--project-path "$PROJECT_DIR" \
		--agent "copilot" \
		--ide "vscode"
	assert_success

	run yq '.name' "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml"
	assert_output "project-sandbox"

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	copilot_agent_compose_file_has_expected_content "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.copilot.yml"
	assert_devcontainer_mode_overlay "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml" "vscode" "project-sandbox-devcontainer"
	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "copilot"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "vscode"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.copilot.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" "false" "false"
	assert_non_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.copilot.override.yml"
}

@test "cli creates layered compose files for codex agent with all standard options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-codex:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-codex:latest : echo 'ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012'"

	run cli \
		--project-path "$PROJECT_DIR" \
		--agent "codex"
	assert_success

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.codex.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml"
	assert_codex_cli_layer "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.codex.yml"
	assert_non_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.codex.override.yml"
}

@test "devcontainer creates centralized runtime files for codex agent with all standard options enabled" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-codex:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-codex:latest : echo 'ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012'"

	run devcontainer \
		--project-path "$PROJECT_DIR" \
		--agent "codex" \
		--ide "vscode"
	assert_success

	run yq '.name' "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml"
	assert_output "project-sandbox"

	assert_cli_base_layer \
		"$PROJECT_DIR/$AGB_PROJECT_DIR/compose/base.yml" \
		"project-sandbox" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	codex_agent_compose_file_has_expected_content "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/agent.codex.yml"
	assert_devcontainer_mode_overlay "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml" "vscode" "project-sandbox-devcontainer"
	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "codex"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "vscode"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_cli_user_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.codex.policy.yaml"
	assert_cli_shared_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" "false" "false"
	assert_non_claude_cli_override "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.codex.override.yml"
}
