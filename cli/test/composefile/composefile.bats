#!/usr/bin/env bats
# bashsupport disable=GrazieInspection
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../lib/composefile.bash
	source "$AGB_LIBDIR/composefile.bash"

	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker-compose.yml"

	cat >"$COMPOSE_FILE" <<'YAML'
services:
  proxy:
    image: placeholder
    volumes: []
  agent:
    image: placeholder
    volumes:
      - ../:/workspace # need at least one entry so that we can add foot comments
    cap_add:
      - SOME_CAPABILITY # need at least one entry so that we can add foot comments
YAML
}

teardown() {
	unstub_all
}

@test "pull_and_pin_image returns local images unchanged" {
	run pull_and_pin_image "my-image:local"
	assert_success
	assert_output "my-image:local"
}

@test "pull_and_pin_image returns unqualified images unchanged" {
	run pull_and_pin_image "alpine"
	assert_success
	assert_output "alpine"
}

@test "pull_and_pin_image pulls and returns digest for remote images" {
	stub docker \
		"pull ghcr.io/example/test:latest : :" \
		"inspect --format='{{index .RepoDigests 0}}' ghcr.io/example/test:latest : echo 'ghcr.io/example/test@sha256:abc123'"

	run pull_and_pin_image "ghcr.io/example/test:latest"

	assert_success
	assert_output "ghcr.io/example/test@sha256:abc123"
}

@test "pull_and_pin_image handles remote images with digests" {
	stub docker \
		"pull ghcr.io/example/test@sha256:abc123 : :" \
		"inspect --format='{{index .RepoDigests 0}}' ghcr.io/example/test@sha256:abc123 : echo 'ghcr.io/example/test@sha256:abc123'"

	run pull_and_pin_image "ghcr.io/example/test@sha256:abc123"

	assert_success
	assert_output "ghcr.io/example/test@sha256:abc123"
}

@test "set_proxy_image sets image with tag" {
	set_proxy_image "$COMPOSE_FILE" "nginx:latest"

	run yq '.services.proxy.image' "$COMPOSE_FILE"
	assert_output "nginx:latest"
}

@test "set_agent_image sets image with digest" {
	set_agent_image "$COMPOSE_FILE" "ghcr.io/example/agent@sha256:def456"

	run yq '.services.agent.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/agent@sha256:def456"
}

@test "add_policy_volume adds policy mount to proxy service" {
	add_policy_volume "$COMPOSE_FILE" "policy.yaml"

	yq -e '.services.proxy.volumes[] | select(. == "policy.yaml:/etc/mitmproxy/policy.yaml:ro")' "$COMPOSE_FILE"
}

@test "add_claude_config_volumes adds CLAUDE.md and settings.json" {
	add_claude_config_volumes "$COMPOSE_FILE"

	run yq '.services.agent.volumes | length' "$COMPOSE_FILE"
	assert_output "3"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$COMPOSE_FILE"
}

@test "add_shell_customizations_volume adds shell.d mount" {
	add_shell_customizations_volume "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$COMPOSE_FILE"
}

@test "add_dotfiles_volume adds dotfiles mount" {
	add_dotfiles_volume "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro")' "$COMPOSE_FILE"
}

@test "add_git_readonly_volume adds .git mount as read-only" {
	add_git_readonly_volume "$COMPOSE_FILE"

	yq -e '.services.agent.volumes[] | select(. == "../.git:/workspace/.git:ro")' "$COMPOSE_FILE"
}

@test "add_idea_readonly_volume adds .idea mount as read-only" {
	add_idea_readonly_volume "$COMPOSE_FILE"

	yq -e '.services.agent.volumes[] | select(. == "../.idea:/workspace/.idea:ro")' "$COMPOSE_FILE"
}

@test "add_vscode_readonly_volume adds .vscode mount as read-only" {
	add_vscode_readonly_volume "$COMPOSE_FILE"

	yq -e '.services.agent.volumes[] | select(. == "../.vscode:/workspace/.vscode:ro")' "$COMPOSE_FILE"
}

assert_jetbrains_capabilities() {
	local compose_file=$1

	yq -e '.services.agent.cap_add[] | select(. == "DAC_OVERRIDE")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "CHOWN")' "$compose_file"
	yq -e '.services.agent.cap_add[] | select(. == "FOWNER")' "$compose_file"

	run yq '.services.agent.cap_add[0] | foot_comment' "$compose_file"
	assert_output "following is required by JetBrains devcontainer"
}

assert_customize_compose_file_common() {
	local compose_file=$1

	# Verify images
	run yq '.services.proxy.image' "$compose_file"
	assert_output "ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"

	run yq '.services.agent.image' "$compose_file"
	assert_output "ghcr.io/mattolson/agent-sandbox-claude@sha256:def456"

	# Verify policy volume on proxy
	yq -e '.services.proxy.volumes[] | select(. == "policy.yaml:/etc/mitmproxy/policy.yaml:ro")' "$compose_file"

	# Verify all agent volumes count (initial + 2 Claude + shell.d + dotfiles + .git + IDE-specific = 7)
	run yq '.services.agent.volumes | length' "$compose_file"
	assert_output "7"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$compose_file"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/dotfiles:/home/dev/.dotfiles:ro")' "$compose_file"

	yq -e '.services.agent.volumes[] | select(. == "../.git:/workspace/.git:ro")' "$compose_file"
}

@test "add_jetbrains_capabilities adds JetBrains-specific capabilities" {
	add_jetbrains_capabilities "$COMPOSE_FILE"

	assert_jetbrains_capabilities "$COMPOSE_FILE"
}

@test "add_volume_entry adds volume when active is true" {
	add_volume_entry "$COMPOSE_FILE" "../test:/workspace/test:ro" "true"

	yq -e '.services.agent.volumes[] | select(. == "../test:/workspace/test:ro")' "$COMPOSE_FILE"
}

@test "add_volume_entry adds comment when active is false" {

	add_volume_entry "$COMPOSE_FILE" "../test:/workspace/test:ro" "false"

	# Verify we have one active volume entry
	run yq '.services.agent.volumes | length' "$COMPOSE_FILE"
	assert_output "1"

	# Verify foot comment was added to the last entry
	run yq '.services.agent.volumes[-1] | foot_comment' "$COMPOSE_FILE"
	assert_output "- ../test:/workspace/test:ro"
}

@test "add_volume_entry appends multiple comments" {
	add_volume_entry "$COMPOSE_FILE" "../test1:/workspace/test1:ro" "false"
	add_volume_entry "$COMPOSE_FILE" "../test2:/workspace/test2:ro" "false"
	add_volume_entry "$COMPOSE_FILE" "../test3:/workspace/test3:ro" "false"

	# Verify we still have one active volume entry
	run yq '.services.agent.volumes | length' "$COMPOSE_FILE"
	assert_output "1"

	# Verify all foot comments were appended
	run yq '.services.agent.volumes[-1] | foot_comment' "$COMPOSE_FILE"
	assert_output - <<EOF
- ../test1:/workspace/test1:ro
- ../test2:/workspace/test2:ro
- ../test3:/workspace/test3:ro
EOF
}

@test "customize_compose_file handles full workflow with all options enabled and jetbrains ide" {
	POLICY_FILE="policy.yaml"
	touch "$BATS_TEST_TMPDIR/$POLICY_FILE"

	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export mount_claude_config="true"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_idea_readonly="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	customize_compose_file "$POLICY_FILE" "$COMPOSE_FILE" "claude" "jetbrains"

	assert_customize_compose_file_common "$COMPOSE_FILE"
	yq -e '.services.agent.volumes[] | select(. == "../.idea:/workspace/.idea:ro")' "$COMPOSE_FILE"
	assert_jetbrains_capabilities "$COMPOSE_FILE"
}

@test "customize_compose_file handles full workflow with all options enabled and vscode ide" {
	POLICY_FILE="policy.yaml"
	touch "$BATS_TEST_TMPDIR/$POLICY_FILE"

	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export mount_claude_config="true"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"
	export mount_git_readonly="true"
	export mount_vscode_readonly="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	customize_compose_file "$POLICY_FILE" "$COMPOSE_FILE" "claude" "vscode"

	assert_customize_compose_file_common "$COMPOSE_FILE"
	yq -e '.services.agent.volumes[] | select(. == "../.vscode:/workspace/.vscode:ro")' "$COMPOSE_FILE"
}
