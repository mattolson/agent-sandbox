#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/edit/policy
	source "$AGB_LIBEXECDIR/edit/policy"

	mkdir -p "$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR"
	POLICY_FILE="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-claude.yaml"
	touch "$POLICY_FILE"
}

teardown() {
	unstub_all
}

@test "policy opens editor for default pattern" {
	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
}

@test "policy filters by mode" {
	POLICY_FILE_CLI="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-cli-claude.yaml"
	POLICY_FILE_DEV="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-claude.yaml"
	touch "$POLICY_FILE_CLI" "$POLICY_FILE_DEV"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE_CLI : :"

	cd "$BATS_TEST_TMPDIR"
	run policy --mode cli
	assert_success
}

@test "policy filters by agent" {
	POLICY_FILE_CURSOR="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-cursor.yaml"
	POLICY_FILE_CLAUDE="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-claude.yaml"
	touch "$POLICY_FILE_CURSOR" "$POLICY_FILE_CLAUDE"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE_CURSOR : :"

	cd "$BATS_TEST_TMPDIR"
	run policy --agent cursor
	assert_success
}

@test "policy filters by mode and agent" {
	POLICY_FILE_SPECIFIC="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-cli-cursor.yaml"
	touch "$POLICY_FILE_SPECIFIC" \
		"$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-cursor.yaml" \
		"$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-cli-claude.yaml" \
		"$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-claude.yaml"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE_SPECIFIC : :"

	cd "$BATS_TEST_TMPDIR"
	run policy --mode cli --agent cursor
	assert_success
}

@test "policy warns when multiple files match and uses first" {
	POLICY_FILE_1="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-agent1.yaml"
	POLICY_FILE_2="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/policy-dev-agent2.yaml"
	touch "$POLICY_FILE_1" "$POLICY_FILE_2"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE_1 : :"

	cd "$BATS_TEST_TMPDIR"
	run policy --mode dev
	assert_success
	assert_output --partial "Multiple policy files found matching pattern"
}

@test "policy restarts proxy when file modified and proxy running" {
	mkdir -p "$BATS_TEST_TMPDIR/.devcontainer"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/.devcontainer/docker-compose.yml"
	touch "$COMPOSE_FILE"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : sleep 1 && touch '$POLICY_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps proxy --status running --quiet : echo 'proxy-container-id'" \
		"compose -f $COMPOSE_FILE restart proxy : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_output --partial "Restarting proxy"
}

@test "policy skips restart when file unchanged" {
	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : true"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
	assert_output --partial "Policy file unchanged. Skipping restart."
}

@test "policy skips restart when proxy not running" {
	mkdir -p "$BATS_TEST_TMPDIR/.devcontainer"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/.devcontainer/docker-compose.yml"
	touch "$COMPOSE_FILE"

	unset -f open_editor
	stub open_editor \
		"$POLICY_FILE : sleep 1 && touch '$POLICY_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps proxy --status running --quiet : :"

	cd "$BATS_TEST_TMPDIR"
	run policy
	assert_success
	assert_output --partial "proxy service is not running. Skipping restart."
}
