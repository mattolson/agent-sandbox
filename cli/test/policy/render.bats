#!/usr/bin/env bats

setup() {
	load test_helper

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	COMPOSE_DIR="$PROJECT_DIR/$AGB_PROJECT_DIR/compose"
	POLICY_DIR="$PROJECT_DIR/$AGB_PROJECT_DIR/policy"

	mkdir -p "$PROJECT_DIR/.git" "$COMPOSE_DIR" "$POLICY_DIR"
	touch \
		"$COMPOSE_DIR/base.yml" \
		"$COMPOSE_DIR/agent.claude.yml" \
		"$COMPOSE_DIR/user.override.yml" \
		"$COMPOSE_DIR/user.agent.claude.override.yml"
	touch "$POLICY_DIR/user.policy.yaml" "$POLICY_DIR/user.agent.claude.policy.yaml"
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

@test "policy config runs the proxy-side render helper through layered compose" {
	stub docker \
		"compose -f $COMPOSE_DIR/base.yml -f $COMPOSE_DIR/agent.claude.yml -f $COMPOSE_DIR/user.override.yml -f $COMPOSE_DIR/user.agent.claude.override.yml run --rm --no-deps -T --entrypoint /usr/local/bin/render-policy proxy : echo 'services: []'"

	cd "$PROJECT_DIR"
	run "$AGB_LIBEXECDIR/policy/config"
	assert_success
	assert_output "services: []"
}

@test "policy config runs the proxy-side render helper through centralized devcontainer compose" {
	local sidecar_root="$BATS_TEST_TMPDIR/devcontainer-project"
	local compose_dir="$sidecar_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.claude.yml"
	local mode_file="$compose_dir/mode.devcontainer.yml"
	local shared_override="$compose_dir/user.override.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	mkdir -p "$sidecar_root/.git" "$sidecar_root/.devcontainer" "$sidecar_root/$AGB_PROJECT_DIR/compose" "$sidecar_root/$AGB_PROJECT_DIR/policy"
	touch "$sidecar_root/.devcontainer/devcontainer.json" "$base_file" "$agent_file" "$mode_file" "$shared_override" "$agent_override"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=claude" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=devcontainer-project-sandbox" > "$sidecar_root/$AGB_PROJECT_DIR/active-target.env"

	stub docker \
		"compose -f $base_file -f $agent_file -f $mode_file -f $shared_override -f $agent_override run --rm --no-deps -T --entrypoint /usr/local/bin/render-policy proxy : echo 'services: [claude, vscode]'"

	ensure_devcontainer_runtime_files() { :; }

	cd "$sidecar_root"
	run "$AGB_LIBEXECDIR/policy/config"
	assert_success
	assert_output "services: [claude, vscode]"
}

@test "policy render remains an alias for policy config" {
	stub docker \
		"compose -f $COMPOSE_DIR/base.yml -f $COMPOSE_DIR/agent.claude.yml -f $COMPOSE_DIR/user.override.yml -f $COMPOSE_DIR/user.agent.claude.override.yml run --rm --no-deps -T --entrypoint /usr/local/bin/render-policy proxy : echo 'services: []'"

	cd "$PROJECT_DIR"
	run "$AGB_LIBEXECDIR/policy/render"
	assert_success
	assert_output "services: []"
}
