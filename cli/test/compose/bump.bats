#!/usr/bin/env bats

setup() {
    load test_helper
    # shellcheck source=../../libexec/compose/bump
    source "$AGB_LIBEXECDIR/compose/bump"

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
