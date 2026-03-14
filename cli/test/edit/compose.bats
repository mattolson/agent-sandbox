#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/edit/compose
	source "$AGB_LIBEXECDIR/edit/compose"

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

@test "edit opens shared user override for layered CLI projects" {
	local compose_dir="$BATS_TEST_TMPDIR/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"

	mkdir -p "$compose_dir" "$BATS_TEST_TMPDIR/.git"
	touch "$compose_dir/base.yml" "$override_file"

	unset -f open_editor
	stub open_editor \
		"$override_file : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
}

@test "edit opens shared override for centralized devcontainer projects" {
	local repo_root="$BATS_TEST_TMPDIR/devcontainer-project"
	local user_file="$repo_root/$AGB_PROJECT_DIR/compose/user.override.yml"

	mkdir -p "$repo_root/.devcontainer" "$repo_root/$AGB_PROJECT_DIR/compose" "$repo_root/.git"
	touch "$repo_root/.devcontainer/devcontainer.json" "$repo_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml" "$user_file"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=sidecar-sandbox" > "$repo_root/$AGB_PROJECT_DIR/active-target.env"

	unset -f open_editor
	stub open_editor \
		"$user_file : :"

	cd "$repo_root"
	run edit
	assert_success
}

@test "edit restarts containers when file modified and containers running (default)" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps --status running --quiet : echo running" \
		"compose -f $COMPOSE_FILE up -d : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified. Restarting containers..."
	refute_output --partial "agentbox up -d"
}

@test "edit confirms save when file modified and no containers running" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps --status running --quiet : :"

	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified."
	refute_output --partial "agentbox up -d"
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

@test "edit with --no-restart warns when modified and containers running" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps --status running --quiet : echo running"

	cd "$BATS_TEST_TMPDIR"
	run edit --no-restart
	assert_success
	assert_output --partial "Compose file was modified, and you have containers running."
	assert_output --partial "agentbox up -d"
}

@test "edit respects AGENTBOX_NO_RESTART env var when modified and containers running" {
	unset -f open_editor
	stub open_editor \
		"$COMPOSE_FILE : sleep 1 && touch '$COMPOSE_FILE'"

	stub docker \
		"compose -f $COMPOSE_FILE ps --status running --quiet : echo running"

	export AGENTBOX_NO_RESTART=true
	cd "$BATS_TEST_TMPDIR"
	run edit
	assert_success
	assert_output --partial "Compose file was modified, and you have containers running."
	assert_output --partial "agentbox up -d"
	unset AGENTBOX_NO_RESTART
}
