#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/bump/bump
	source "$AGB_LIBEXECDIR/bump/bump"
}

teardown() {
	unstub_all
}

@test "bump fails fast for legacy single-file layouts" {
	local test_root="$BATS_TEST_TMPDIR/repo"

	mkdir -p "$test_root/$AGB_PROJECT_DIR" "$test_root/.git"
	touch "$test_root/$AGB_PROJECT_DIR/docker-compose.yml"

	cd "$test_root"
	run bump

	assert_failure
	assert_output --partial "does not support the legacy single-file layout"
	assert_output --partial ".agent-sandbox/docker-compose.legacy.yml"
	assert_output --partial "docs/upgrades/m8-layered-layout.md"
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
