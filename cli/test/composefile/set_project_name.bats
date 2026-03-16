#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/composefile.bash
	source "$AGB_LIBDIR/composefile.bash"

	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker-compose.yml"

	cat >"$COMPOSE_FILE" <<'YAML'
services:
  proxy:
    image: placeholder
  agent:
    image: placeholder
YAML
}

teardown() {
	unstub_all
}

@test "set_project_name inserts name key at top of compose file" {
	set_project_name "$COMPOSE_FILE" "my-project-sandbox"

	run yq '.name' "$COMPOSE_FILE"
	assert_output "my-project-sandbox"

	# Verify name appears before services in the file
	local name_line services_line
	name_line=$(grep -n '^name:' "$COMPOSE_FILE" | head -1 | cut -d: -f1)
	services_line=$(grep -n '^services:' "$COMPOSE_FILE" | head -1 | cut -d: -f1)
	(( name_line < services_line ))
}

@test "set_project_name preserves existing services" {
	set_project_name "$COMPOSE_FILE" "test-sandbox"

	run yq '.services.proxy.image' "$COMPOSE_FILE"
	assert_output "placeholder"

	run yq '.services.agent.image' "$COMPOSE_FILE"
	assert_output "placeholder"
}

@test "set_project_name does not rewrite file when name is unchanged" {
	set_project_name "$COMPOSE_FILE" "stable-sandbox"

	local initial_mtime
	initial_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	sleep 1
	set_project_name "$COMPOSE_FILE" "stable-sandbox"

	local final_mtime
	final_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	assert_equal "$final_mtime" "$initial_mtime"
}

@test "set_service_environment_var does not rewrite file when value is unchanged" {
	cat >"$COMPOSE_FILE" <<'YAML'
services:
  proxy:
    image: placeholder
    environment:
      - KEEP=1
      - AGENTBOX_ACTIVE_AGENT=claude
YAML

	set_service_environment_var "$COMPOSE_FILE" "proxy" "AGENTBOX_ACTIVE_AGENT" "claude"

	local initial_mtime
	initial_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	sleep 1
	set_service_environment_var "$COMPOSE_FILE" "proxy" "AGENTBOX_ACTIVE_AGENT" "claude"

	local final_mtime
	final_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	assert_equal "$final_mtime" "$initial_mtime"

	run yq '.services.proxy.environment[]' "$COMPOSE_FILE"
	assert_output $'KEEP=1\nAGENTBOX_ACTIVE_AGENT=claude'
}

@test "remove_service_volume does not rewrite file when volume is absent" {
	cat >"$COMPOSE_FILE" <<'YAML'
services:
  proxy:
    image: placeholder
    volumes:
      - KEEP:/keep
YAML

	remove_service_volume "$COMPOSE_FILE" "proxy" "../policy-cli-claude.yaml:/etc/mitmproxy/policy.yaml:ro"

	local initial_mtime
	initial_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	sleep 1
	remove_service_volume "$COMPOSE_FILE" "proxy" "../policy-cli-claude.yaml:/etc/mitmproxy/policy.yaml:ro"

	local final_mtime
	final_mtime="$(get_file_mtime "$COMPOSE_FILE")"

	assert_equal "$final_mtime" "$initial_mtime"

	run yq '.services.proxy.volumes[]' "$COMPOSE_FILE"
	assert_output "KEEP:/keep"
}

@test "pull_and_pin_image fails when pull fails and no local copy exists" {
	stub docker \
		"pull ghcr.io/example/fail:latest : exit 1" \
		"image inspect ghcr.io/example/fail:latest : exit 1"

	run pull_and_pin_image "ghcr.io/example/fail:latest"
	assert_failure
	assert_output --partial "no local copy exists"
}

@test "pull_and_pin_image falls back to local image when pull fails" {
	stub docker \
		"pull ghcr.io/example/local-only:latest : exit 1" \
		"image inspect ghcr.io/example/local-only:latest : :"

	run pull_and_pin_image "ghcr.io/example/local-only:latest"
	assert_success
	assert_output --partial "using local image"
	assert_output --partial "ghcr.io/example/local-only:latest"
}

@test "pull_and_pin_image propagates docker inspect failure" {
	stub docker \
		"pull ghcr.io/example/test:latest : :" \
		"inspect --format='{{index .RepoDigests 0}}' ghcr.io/example/test:latest : exit 1"

	run pull_and_pin_image "ghcr.io/example/test:latest"
	assert_failure
}
