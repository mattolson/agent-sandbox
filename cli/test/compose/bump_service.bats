#!/usr/bin/env bats

setup() {
	load test_helper
	source "$AGB_LIBDIR/composefile.bash"
	source "$AGB_LIBDIR/logging.bash"
	source "$AGB_LIBEXECDIR/compose/bump"

	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker-compose.yml"
}

teardown() {
	unstub_all
}

@test "bump_service skips local images with :local suffix" {
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  test:
    image: my-image:local
EOF

	bump_service "$COMPOSE_FILE" "test"

	run yq '.services.test.image' "$COMPOSE_FILE"
	assert_output "my-image:local"
}

@test "bump_service skips unqualified images" {
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  test:
    image: alpine
EOF

	bump_service "$COMPOSE_FILE" "test"

	run yq '.services.test.image' "$COMPOSE_FILE"
	assert_output "alpine"
}

@test "bump_service pulls and updates image with tag" {
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  test:
    image: ghcr.io/example/test:latest
EOF

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/example/test:latest : echo 'ghcr.io/example/test@sha256:abc123'"

	bump_service "$COMPOSE_FILE" "test"

	run yq '.services.test.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/test@sha256:abc123"
}

@test "bump_service updates image with existing digest" {
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  test:
    image: ghcr.io/example/test@sha256:old123
EOF

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/example/test : echo 'ghcr.io/example/test@sha256:new456'"

	bump_service "$COMPOSE_FILE" "test"

	run yq '.services.test.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/test@sha256:new456"
}

@test "bump_service works when already at latest digest" {
	cat >"$COMPOSE_FILE" <<'EOF'
services:
  test:
    image: ghcr.io/example/test@sha256:abc123
EOF

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/example/test : echo 'ghcr.io/example/test@sha256:abc123'"

	bump_service "$COMPOSE_FILE" "test"

	run yq '.services.test.image' "$COMPOSE_FILE"
	assert_output "ghcr.io/example/test@sha256:abc123"
}
