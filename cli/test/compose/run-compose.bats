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

@test "run-compose uses devcontainer sidecar compose files in managed/user order" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/.devcontainer"
	local managed_file="$compose_dir/docker-compose.base.yml"
	local user_file="$compose_dir/docker-compose.user.override.yml"

	mkdir -p "$compose_dir" "$test_root/.git" "$test_root/$AGB_PROJECT_DIR"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"DEVCONTAINER_PROJECT_NAME=repo-sandbox-devcontainer" > "$test_root/$AGB_PROJECT_DIR/active-target.env"
	touch "$managed_file" "$user_file"

	stub docker \
		"compose -f $managed_file -f $user_file ps : :"

	ensure_devcontainer_runtime_files() { :; }
	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_success
}

@test "run-compose falls back to a legacy single compose file when sidecar layout is not initialized" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/.devcontainer/docker-compose.yml"

	mkdir -p "$test_root/.devcontainer" "$test_root/.git"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file ps : :"

	exec() { "$@"; }

	cd "$test_root"
	run compose ps
	assert_success
}
