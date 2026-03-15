#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/run-compose
	source "$AGB_LIBDIR/run-compose"
}

teardown() {
	unstub_all
}

@test "run-compose uses layered CLI compose files in active-agent order" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"
	local shared_override="$compose_dir/user.override.yml"
	local agent_override="$compose_dir/user.agent.codex.override.yml"

	mkdir -p "$compose_dir" "$test_root/.git"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=codex" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$base_file" "$agent_file" "$shared_override" "$agent_override"

	stub docker \
		"compose -f $base_file -f $agent_file -f $shared_override -f $agent_override ps : :"

	ensure_cli_agent_runtime_files() { :; }
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_success
}

@test "run-compose skips layered CLI runtime sync for read-only commands" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"

	mkdir -p "$compose_dir" "$test_root/.git"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=codex" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$base_file" "$agent_file"

	stub docker \
		"compose -f $base_file -f $agent_file ps : :"

	ensure_cli_agent_runtime_files() {
		echo called > "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.called"
	}
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_success
	[ ! -f "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.called" ]
}

@test "run-compose uses centralized devcontainer compose files in managed/user order" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"
	local mode_file="$compose_dir/mode.devcontainer.yml"
	local shared_override="$compose_dir/user.override.yml"
	local agent_override="$compose_dir/user.agent.codex.override.yml"

	mkdir -p "$compose_dir" "$test_root/.git" "$test_root/$AGB_PROJECT_DIR" "$test_root/.devcontainer"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=repo-sandbox" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$base_file" "$agent_file" "$mode_file" "$shared_override" "$agent_override" "$test_root/.devcontainer/devcontainer.json"

	stub docker \
		"compose -f $base_file -f $agent_file -f $mode_file -f $shared_override -f $agent_override ps : :"

	ensure_devcontainer_runtime_files() { :; }
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_success
}

@test "run-compose syncs devcontainer runtime files for mutating commands only" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"
	local mode_file="$compose_dir/mode.devcontainer.yml"

	mkdir -p "$compose_dir" "$test_root/.git" "$test_root/$AGB_PROJECT_DIR" "$test_root/.devcontainer"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=repo-sandbox" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$base_file" "$agent_file" "$mode_file" "$test_root/.devcontainer/devcontainer.json"

	stub docker \
		"compose -f $base_file -f $agent_file -f $mode_file up -d : :"

	ensure_devcontainer_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	}
	exec() { "$@"; }

	cd "$test_root"
	run compose up -d
	assert_success
	run cat "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	assert_success
	assert_output "$test_root codex"
}

@test "run-compose skips runtime sync when AGENTBOX_SKIP_RUNTIME_SYNC is set" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"

	mkdir -p "$compose_dir" "$test_root/.git"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=codex" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$base_file" "$agent_file"

	stub docker \
		"compose -f $base_file -f $agent_file run --rm proxy : :"

	ensure_cli_agent_runtime_files() {
		echo called > "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.called"
	}
	exec() { "$@"; }

	cd "$test_root"
	AGENTBOX_SKIP_RUNTIME_SYNC=1 run compose run --rm proxy
	assert_success
	[ ! -f "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.called" ]
}

@test "run-compose fails clearly when layered CLI compose file resolution fails" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"

	mkdir -p "$compose_dir" "$test_root/.git"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=codex" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$compose_dir/base.yml"

	require() { :; }
	emit_cli_compose_files() { return 1; }
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_failure
	assert_output --partial "Failed to resolve layered CLI compose files for $test_root."
}

@test "run-compose fails clearly when devcontainer compose file resolution fails" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"

	mkdir -p "$compose_dir" "$test_root/.git" "$test_root/.devcontainer"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=repo-sandbox" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$compose_dir/mode.devcontainer.yml" "$test_root/.devcontainer/devcontainer.json"

	require() { :; }
	emit_devcontainer_compose_files() { return 1; }
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_failure
	assert_output --partial "Failed to resolve devcontainer compose files for $test_root."
}

@test "run-compose fails fast for legacy single-file layouts" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/.devcontainer/docker-compose.yml"

	mkdir -p "$test_root/.devcontainer" "$test_root/.git"
	touch "$compose_file"

	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_failure
	assert_output --partial "does not support the legacy single-file layout"
	assert_output --partial ".devcontainer/docker-compose.legacy.yml"
	assert_output --partial "docs/upgrades/m8-layered-layout.md"
}
