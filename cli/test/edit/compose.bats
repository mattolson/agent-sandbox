#!/usr/bin/env bats

setup() {
	load test_helper

	# shellcheck source=../../libexec/edit/compose
	source "$AGB_LIBEXECDIR/edit/compose"

	REPO_ROOT="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$REPO_ROOT/.git"

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

setup_layered_cli_project() {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local shared_override="$compose_dir/user.override.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	mkdir -p "$compose_dir"
	touch "$compose_dir/base.yml" "$compose_dir/agent.claude.yml" "$shared_override" "$agent_override"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$REPO_ROOT/$AGB_PROJECT_DIR/active-target.env"
}

@test "edit compose fails fast for legacy layouts" {
	mkdir -p "$REPO_ROOT/.devcontainer"
	touch "$REPO_ROOT/.devcontainer/docker-compose.yml"

	cd "$REPO_ROOT"
	run edit

	assert_failure
	assert_output --partial "does not support the legacy single-file layout"
	assert_output --partial ".devcontainer/docker-compose.yml -> .devcontainer/docker-compose.legacy.yml"
	assert_output --partial "docs/upgrades/m8-layered-layout.md"
}

@test "edit opens shared user override for layered CLI projects" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : :"

	cd "$REPO_ROOT"
	run edit
	assert_success
}

@test "edit opens shared override for centralized devcontainer projects" {
	local repo_root="$BATS_TEST_TMPDIR/devcontainer-project"
	local user_file="$repo_root/$AGB_PROJECT_DIR/compose/user.override.yml"

	mkdir -p "$repo_root/.devcontainer" "$repo_root/$AGB_PROJECT_DIR/compose" "$repo_root/.git"
	touch \
		"$repo_root/.devcontainer/devcontainer.json" \
		"$repo_root/$AGB_PROJECT_DIR/compose/mode.devcontainer.yml" \
		"$repo_root/$AGB_PROJECT_DIR/compose/base.yml" \
		"$repo_root/$AGB_PROJECT_DIR/compose/agent.codex.yml" \
		"$user_file"
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

@test "edit restarts containers when file modified and containers running by default" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.claude.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : sleep 1 && touch '$override_file'"
	ensure_cli_agent_runtime_files() { :; }

	stub docker \
		"compose -f $base_file -f $agent_file -f $override_file -f $agent_override ps --status running --quiet : echo running" \
		"compose -f $base_file -f $agent_file -f $override_file -f $agent_override up -d : :"

	cd "$REPO_ROOT"
	run edit

	assert_success
	assert_output --partial "Compose file was modified. Restarting containers..."
	refute_output --partial "agentbox up -d"
}

@test "edit confirms save when file modified and no containers are running" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.claude.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : sleep 1 && touch '$override_file'"
	ensure_cli_agent_runtime_files() { :; }

	stub docker \
		"compose -f $base_file -f $agent_file -f $override_file -f $agent_override ps --status running --quiet : :"

	cd "$REPO_ROOT"
	run edit

	assert_success
	assert_output --partial "Compose file was modified."
	refute_output --partial "agentbox up -d"
}

@test "edit reports no changes when file is unchanged" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : :"

	cd "$REPO_ROOT"
	run edit

	assert_success
	assert_output --partial "No changes detected."
}

@test "edit with --no-restart warns when modified and containers are running" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.claude.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : sleep 1 && touch '$override_file'"
	ensure_cli_agent_runtime_files() { :; }

	stub docker \
		"compose -f $base_file -f $agent_file -f $override_file -f $agent_override ps --status running --quiet : echo running"

	cd "$REPO_ROOT"
	run edit --no-restart

	assert_success
	assert_output --partial "Compose file was modified, and you have containers running."
	assert_output --partial "agentbox up -d"
}

@test "edit respects AGENTBOX_NO_RESTART when modified and containers are running" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local override_file="$compose_dir/user.override.yml"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.claude.yml"
	local agent_override="$compose_dir/user.agent.claude.override.yml"

	setup_layered_cli_project

	unset -f open_editor
	stub open_editor \
		"$override_file : sleep 1 && touch '$override_file'"
	ensure_cli_agent_runtime_files() { :; }

	stub docker \
		"compose -f $base_file -f $agent_file -f $override_file -f $agent_override ps --status running --quiet : echo running"

	export AGENTBOX_NO_RESTART=true
	cd "$REPO_ROOT"
	run edit

	assert_success
	assert_output --partial "Compose file was modified, and you have containers running."
	assert_output --partial "agentbox up -d"
	unset AGENTBOX_NO_RESTART
}
