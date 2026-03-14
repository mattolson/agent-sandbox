#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/edit/policy
	source "$AGB_LIBEXECDIR/edit/policy"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	COMPOSE_DIR="$PROJECT_DIR/$AGB_PROJECT_DIR/compose"
	POLICY_DIR="$PROJECT_DIR/$AGB_PROJECT_DIR/policy"
	SHARED_POLICY_FILE="$POLICY_DIR/user.policy.yaml"
	ACTIVE_AGENT_POLICY_FILE="$POLICY_DIR/user.agent.claude.policy.yaml"
	INACTIVE_AGENT_POLICY_FILE="$POLICY_DIR/user.agent.codex.policy.yaml"
	SHARED_OVERRIDE_FILE="$COMPOSE_DIR/user.override.yml"
	ACTIVE_AGENT_OVERRIDE_FILE="$COMPOSE_DIR/user.agent.claude.override.yml"

	mkdir -p "$PROJECT_DIR/.git" "$COMPOSE_DIR" "$POLICY_DIR"
	touch \
		"$COMPOSE_DIR/base.yml" \
		"$COMPOSE_DIR/agent.claude.yml" \
		"$COMPOSE_DIR/agent.codex.yml" \
		"$SHARED_OVERRIDE_FILE" \
		"$ACTIVE_AGENT_OVERRIDE_FILE"
	touch "$SHARED_POLICY_FILE" "$ACTIVE_AGENT_POLICY_FILE"
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

@test "policy opens shared layered CLI policy by default" {
	unset -f open_editor
	stub open_editor \
		"$SHARED_POLICY_FILE : :"

	cd "$PROJECT_DIR"
	run policy
	assert_success
}

@test "policy opens agent-specific layered CLI policy and scaffolds it when missing" {
	rm -f "$INACTIVE_AGENT_POLICY_FILE"

	unset -f open_editor
	stub open_editor \
		"$INACTIVE_AGENT_POLICY_FILE : :"

	cd "$PROJECT_DIR"
	run policy --agent codex
	assert_success
	assert [ -f "$INACTIVE_AGENT_POLICY_FILE" ]
}

@test "policy restarts proxy when shared layered policy is modified and proxy is running" {
	unset -f open_editor
	stub open_editor \
		"$SHARED_POLICY_FILE : sleep 1 && touch '$SHARED_POLICY_FILE'"

	stub docker \
		"compose -f $COMPOSE_DIR/base.yml -f $COMPOSE_DIR/agent.claude.yml -f $SHARED_OVERRIDE_FILE -f $ACTIVE_AGENT_OVERRIDE_FILE ps proxy --status running --quiet : echo 'proxy-container-id'" \
		"compose -f $COMPOSE_DIR/base.yml -f $COMPOSE_DIR/agent.claude.yml -f $SHARED_OVERRIDE_FILE -f $ACTIVE_AGENT_OVERRIDE_FILE restart proxy : :"

	cd "$PROJECT_DIR"
	run policy
	assert_success
	assert_output --partial "Restarting proxy"
}

@test "policy skips restart for inactive layered agent-specific policy changes" {
	touch "$INACTIVE_AGENT_POLICY_FILE"

	unset -f open_editor
	stub open_editor \
		"$INACTIVE_AGENT_POLICY_FILE : sleep 1 && touch '$INACTIVE_AGENT_POLICY_FILE'"

	cd "$PROJECT_DIR"
	run policy --agent codex
	assert_success
	assert_output --partial "inactive agent 'codex'"
}

@test "policy falls back to legacy devcontainer policy lookup" {
	local devcontainer_root="$BATS_TEST_TMPDIR/devcontainer-project"
	local legacy_policy_file="$devcontainer_root/$AGB_PROJECT_DIR/policy-devcontainer-claude.yaml"

	mkdir -p "$devcontainer_root/.git" "$devcontainer_root/$AGB_PROJECT_DIR"
	touch "$legacy_policy_file"

	unset -f open_editor
	stub open_editor \
		"$legacy_policy_file : :"

	cd "$devcontainer_root"
	run policy --mode devcontainer --agent claude
	assert_success
}

@test "policy defaults devcontainer sidecar projects to the shared layered policy file" {
	local sidecar_root="$BATS_TEST_TMPDIR/devcontainer-sidecar-project"
	local shared_policy_file="$sidecar_root/$AGB_PROJECT_DIR/policy/user.policy.yaml"

	mkdir -p "$sidecar_root/.git" "$sidecar_root/$AGB_PROJECT_DIR/compose" "$sidecar_root/$AGB_PROJECT_DIR/policy" "$sidecar_root/.devcontainer"
	touch "$shared_policy_file" "$sidecar_root/.devcontainer/devcontainer.json" "$sidecar_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=claude" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=devcontainer-sidecar-sandbox" > "$sidecar_root/$AGB_PROJECT_DIR/active-target.env"

	unset -f open_editor
	stub open_editor \
		"$shared_policy_file : :"

	cd "$sidecar_root"
	run policy
	assert_success
}

@test "policy treats --mode devcontainer as the shared layered policy surface in centralized layouts" {
	local sidecar_root="$BATS_TEST_TMPDIR/devcontainer-project"
	local shared_policy_file="$sidecar_root/$AGB_PROJECT_DIR/policy/user.policy.yaml"

	mkdir -p "$sidecar_root/.git" "$sidecar_root/$AGB_PROJECT_DIR/compose" "$sidecar_root/$AGB_PROJECT_DIR/policy" "$sidecar_root/.devcontainer"
	touch "$shared_policy_file" "$sidecar_root/.devcontainer/devcontainer.json" "$sidecar_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=claude" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=devcontainer-sidecar-sandbox" > "$sidecar_root/$AGB_PROJECT_DIR/active-target.env"

	unset -f open_editor
	stub open_editor \
		"$shared_policy_file : :"

	cd "$sidecar_root"
	run policy --mode devcontainer
	assert_success
}
