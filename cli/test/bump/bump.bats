#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/bump/bump
	source "$AGB_LIBEXECDIR/bump/bump"

	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker-compose.yml"
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  proxy:
    image: ghcr.io/example/proxy:latest
  agent:
    image: ghcr.io/example/agent:latest
EOF
}

teardown() {
	unstub_all
}

@test "bump processes all services" {
	unset -f find_compose_file
	stub find_compose_file \
		": echo '$COMPOSE_FILE'"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/example/proxy:latest : echo 'ghcr.io/example/proxy@sha256:abc123'" \
		"ghcr.io/example/agent:latest : echo 'ghcr.io/example/agent@sha256:def456'"

	bump

	# Verify both images were updated
	run yq '.services.proxy.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/proxy@sha256:abc123"

	run yq '.services.agent.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/agent@sha256:def456"
}

@test "bump updates managed layered CLI files and skips missing agent layers" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local claude_file="$compose_dir/agent.claude.yml"

	mkdir -p "$compose_dir" "$test_root/.git"
	cat >"$base_file" <<'EOF'
services:
  proxy:
    image: ghcr.io/example/proxy:latest
EOF
	cat >"$claude_file" <<'EOF'
services:
  agent:
    image: ghcr.io/example/claude:latest
EOF

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/example/proxy:latest : echo 'ghcr.io/example/proxy@sha256:abc123'" \
		"ghcr.io/example/claude:latest : echo 'ghcr.io/example/claude@sha256:def456'"

	cd "$test_root"
	run bump
	assert_success
	assert_output --partial "copilot layer: not initialized, skipping"
	assert_output --partial "codex layer: not initialized, skipping"

	run yq '.services.proxy.image' "$base_file"
	assert_output "ghcr.io/example/proxy@sha256:abc123"

	run yq '.services.agent.image' "$claude_file"
	assert_output "ghcr.io/example/claude@sha256:def456"
}
