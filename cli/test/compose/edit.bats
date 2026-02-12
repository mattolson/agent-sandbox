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

@test "edit restarts docker compose when file modified" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE up -d : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified. Restarting docker compose..."
}

@test "edit skips restart when file unchanged" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "No changes detected. Skipping restart."
}
