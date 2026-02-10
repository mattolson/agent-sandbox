#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	source "$AGB_LIBDIR/composefile.bash"

	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker-compose.yml"

	cat >"$COMPOSE_FILE" <<'EOF'
services:
  proxy:
    image: placeholder
    volumes: []
  agent:
    image: placeholder
    volumes: []
EOF
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
	assert_output "2"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$COMPOSE_FILE"
}

@test "add_shell_customizations_volume adds shell.d mount" {
	# shellcheck disable=SC2016
	export AGB_HOME_PATTERN='${HOME}/.config/agent-sandbox'

	add_shell_customizations_volume "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$COMPOSE_FILE"
}

@test "add_dotfiles_volume adds dotfiles mount" {
	add_dotfiles_volume "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.dotfiles:/home/dev/.dotfiles:ro")' "$COMPOSE_FILE"
}

@test "customize_compose_file handles full workflow with all options enabled" {
	POLICY_FILE="policy.yaml"
	touch "$BATS_TEST_TMPDIR/$POLICY_FILE"
	# shellcheck disable=SC2016
	export AGB_HOME_PATTERN='${HOME}/.config/agent-sandbox'

	export proxy_image="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export agent_image="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export mount_claude_config="true"
	export enable_shell_customizations="true"
	export enable_dotfiles="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	customize_compose_file "claude" "$POLICY_FILE" "$COMPOSE_FILE"

	# Verify images
	run yq '.services.proxy.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123"

	run yq '.services.agent.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/mattolson/agent-sandbox-claude@sha256:def456"

	# Verify policy volume on proxy
	yq -e '.services.proxy.volumes[] | select(. == "policy.yaml:/etc/mitmproxy/policy.yaml:ro")' "$COMPOSE_FILE"

	# Verify all agent volumes are present (2 Claude + shell.d + dotfiles = 4)
	run yq '.services.agent.volumes | length' "$COMPOSE_FILE"
	assert_output "4"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro")' "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.claude/settings.json:/home/dev/.claude/settings.json:ro")' "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.config/agent-sandbox/shell.d:/home/dev/.config/agent-sandbox/shell.d:ro")' "$COMPOSE_FILE"

	# shellcheck disable=SC2016
	yq -e '.services.agent.volumes[] | select(. == "${HOME}/.dotfiles:/home/dev/.dotfiles:ro")' "$COMPOSE_FILE"
}
