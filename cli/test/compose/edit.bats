#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/compose/edit
	source "$AGB_LIBEXECDIR/compose/edit"

	mkdir -p "$BATS_TEST_TMPDIR/.devcontainer"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/.devcontainer/docker-compose.yml"
	touch "$COMPOSE_FILE"
}

teardown() {
	unstub_all
}

@test "edit opens compose file in editor" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
}

@test "edit warns when file modified and containers running" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps agent --status running --quiet : echo running"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified"
	assert_output --partial "agentbox compose up -d"
}

@test "edit confirms save when file modified and no containers running" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps agent --status running --quiet : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified."
	refute_output --partial "agentbox compose up -d"
}

@test "edit reports no changes when file unchanged" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "No changes detected."
}
