#!/usr/bin/env bats

setup() {
	load test_helper

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	COMPOSE_DIR="$PROJECT_DIR/$AGB_PROJECT_DIR/compose"

	mkdir -p "$PROJECT_DIR/.git" "$COMPOSE_DIR" "$PROJECT_DIR/$AGB_PROJECT_DIR"
	touch \
		"$COMPOSE_DIR/base.yml" \
		"$COMPOSE_DIR/agent.claude.yml" \
		"$COMPOSE_DIR/user.override.yml" \
		"$COMPOSE_DIR/user.agent.claude.override.yml"
	touch "$PROJECT_DIR/$AGB_PROJECT_DIR/user.policy.yaml" "$PROJECT_DIR/$AGB_PROJECT_DIR/user.agent.claude.policy.yaml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/$AGB_PROJECT_DIR/active-target.env"

	local bin_dir="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin_dir"
	cat > "$bin_dir/yq" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$bin_dir/yq"
	PATH="$bin_dir:$PATH"
}

teardown() {
	unstub_all
}

@test "policy render runs the proxy-side render helper through layered compose" {
	stub docker \
		"compose -f $COMPOSE_DIR/base.yml -f $COMPOSE_DIR/agent.claude.yml -f $COMPOSE_DIR/user.override.yml -f $COMPOSE_DIR/user.agent.claude.override.yml run --rm --no-deps -T --entrypoint /usr/local/bin/render-policy proxy : echo 'services: []'"

	cd "$PROJECT_DIR"
	run "$AGB_LIBEXECDIR/policy/render"
	assert_success
	assert_output "services: []"
}
