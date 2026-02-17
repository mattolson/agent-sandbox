#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# This is a regression test verifying that docker-compose configuration is generated correctly.

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/cli
	source "$AGB_LIBEXECDIR/init/cli"
	# shellcheck source=../../libexec/init/devcontainer
	source "$AGB_LIBEXECDIR/init/devcontainer"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR/$AGB_PROJECT_DIR"

	POLICY_FILE="$AGB_PROJECT_DIR/policy.yaml"
	touch "$PROJECT_DIR/$POLICY_FILE"
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

assert_agent_service_base() {
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

assert_common_volumes() {
	local compose_file=$1

	yq -e '.services.agent.volumes[] | select(. == "../:/workspace")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../.agent-sandbox/:/workspace/.agent-sandbox/:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "proxy-ca:/etc/mitmproxy:ro")' "$compose_file"
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

assert_customization_volumes() {
	local compose_file=$1

	yq -e '.services.proxy.volumes[] | select(. == "../'"$AGB_PROJECT_DIR"'/policy.yaml:/etc/mitmproxy/policy.yaml:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../.git:/workspace/.git:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../.idea:/workspace/.idea:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../.vscode:/workspace/.vscode:ro")' "$compose_file"
}

assert_devcontainer_volume() {
	local compose_file=$1

	yq -e '.services.agent.volumes[] | select(. == ".:/workspace/.devcontainer:ro")' "$compose_file"
}

claude_agent_compose_file_has_expected_content() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	assert_proxy_service "$compose_file" "ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	assert_agent_service_base "$compose_file" "ghcr.io/mattolson/agent-sandbox-claude@sha256:def456"

	yq -e '.services.agent.environment[] | select(. == "CLAUDE_CONFIG_DIR=/home/dev/.claude")' "$compose_file"

	assert_common_environment_vars "$compose_file"
	assert_common_volumes "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "claude-state:/home/dev/.claude")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "claude-history:/commandhistory")' "$compose_file"

	assert_named_volumes "$compose_file" "claude-state" "claude-history" "proxy-state" "proxy-ca"
	assert_customization_volumes "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$compose_file"
}

copilot_agent_compose_file_has_expected_content() {
	local compose_file=$1

	assert [ -f "$compose_file" ]

	assert_proxy_service "$compose_file" "ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"
	assert_agent_service_base "$compose_file" "ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789"
	assert_common_environment_vars "$compose_file"
	assert_common_volumes "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "copilot-state:/home/dev/.copilot")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "copilot-history:/commandhistory")' "$compose_file"

	assert_named_volumes "$compose_file" "copilot-state" "copilot-history" "proxy-state" "proxy-ca"
	assert_customization_volumes "$compose_file"
	# shellcheck disable=SC2016
	run yq '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$compose_file"
	assert_output ""
}

@test "cli creates docker-compose.yml for claude agent with all options enabled" {
	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export mount_claude_config="true"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_idea_readonly="true"
	export mount_vscode_readonly="true"
	export edit_compose_file="false"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run cli "claude" "$PROJECT_DIR" "$POLICY_FILE"
	assert_success
	assert_output --regexp ".*Compose file created at $PROJECT_DIR/$AGB_PROJECT_DIR/docker-compose.yml"

	claude_agent_compose_file_has_expected_content "$PROJECT_DIR/$AGB_PROJECT_DIR/docker-compose.yml"
}

@test "devcontainer creates docker-compose.yml for claude agent with all options enabled" {
	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export mount_claude_config="true"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_idea_readonly="true"
	export mount_vscode_readonly="true"
	export edit_compose_file="false"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run devcontainer "claude" "$PROJECT_DIR" "$POLICY_FILE"
	assert_success
	assert_output --regexp ".*Devcontainer dir created at $PROJECT_DIR/.devcontainer"

	claude_agent_compose_file_has_expected_content "$PROJECT_DIR/.devcontainer/docker-compose.yml"

	assert_devcontainer_volume "$PROJECT_DIR/.devcontainer/docker-compose.yml"
}

@test "cli creates docker-compose.yml for copilot agent with all options enabled" {
	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_idea_readonly="true"
	export mount_vscode_readonly="true"
	export edit_compose_file="false"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run cli "copilot" "$PROJECT_DIR" "$POLICY_FILE"
	assert_success
	assert_output --regexp ".*Compose file created at $PROJECT_DIR/$AGB_PROJECT_DIR/docker-compose.yml"

	copilot_agent_compose_file_has_expected_content "$PROJECT_DIR/$AGB_PROJECT_DIR/docker-compose.yml"
}

@test "devcontainer creates docker-compose.yml for copilot agent with all options enabled" {
	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_idea_readonly="true"
	export mount_vscode_readonly="true"
	export edit_compose_file="false"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run devcontainer "copilot" "$PROJECT_DIR" "$POLICY_FILE"
	assert_success
	assert_output --regexp ".*Devcontainer dir created at $PROJECT_DIR/.devcontainer"

	copilot_agent_compose_file_has_expected_content "$PROJECT_DIR/.devcontainer/docker-compose.yml"

	assert_devcontainer_volume "$PROJECT_DIR/.devcontainer/docker-compose.yml"
}
