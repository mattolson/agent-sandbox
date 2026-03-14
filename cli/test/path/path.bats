#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/path.bash
	source "$AGB_LIBDIR/path.bash"
	# shellcheck source=../../lib/cli-compose.bash
	source "$AGB_LIBDIR/cli-compose.bash"
}

teardown() {
	unstub_all
}

# verify_relative_path tests

@test "verify_relative_path rejects non-directory base" {
	run verify_relative_path "/nonexistent/path" "file.txt"
	assert_failure
	assert_output --partial "base is not a directory"
}

@test "verify_relative_path rejects absolute path" {
	run verify_relative_path "$BATS_TEST_TMPDIR" "/absolute/path.txt"
	assert_failure
	assert_output --partial "path must be relative, not absolute"
}

@test "verify_relative_path rejects missing file" {
	run verify_relative_path "$BATS_TEST_TMPDIR" "nonexistent.txt"
	assert_failure
	assert_output --partial "file not found"
}

@test "verify_relative_path accepts valid relative path" {
	touch "$BATS_TEST_TMPDIR/existing.txt"

	run verify_relative_path "$BATS_TEST_TMPDIR" "existing.txt"
	assert_success
}

# derive_project_name tests

@test "derive_project_name cli mode produces {dir}-sandbox" {
	run derive_project_name "/home/user/myproject" "cli"
	assert_success
	assert_output "myproject-sandbox"
}

@test "derive_project_name devcontainer mode produces {dir}-sandbox-devcontainer" {
	run derive_project_name "/home/user/myproject" "devcontainer"
	assert_success
	assert_output "myproject-sandbox-devcontainer"
}

@test "strip_mode_suffix removes one trailing devcontainer suffix" {
	run strip_mode_suffix "myproject-sandbox-devcontainer" "devcontainer"
	assert_success
	assert_output "myproject-sandbox"
}

@test "derive_project_name uses basename of path" {
	run derive_project_name "/deeply/nested/path/coolproject" "cli"
	assert_success
	assert_output "coolproject-sandbox"
}

# get_file_mtime tests

@test "get_file_mtime returns numeric timestamp" {
	local testfile="$BATS_TEST_TMPDIR/mtimefile"
	touch "$testfile"

	run get_file_mtime "$testfile"
	assert_success
	assert_output --regexp '^[0-9]+$'
}

@test "cli_layered_compose_initialized detects layered CLI base file" {
	local test_root="$BATS_TEST_TMPDIR/repo"

	mkdir -p "$test_root/$AGB_PROJECT_DIR/compose"
	refute cli_layered_compose_initialized "$test_root"

	touch "$test_root/$AGB_PROJECT_DIR/compose/base.yml"
	run cli_layered_compose_initialized "$test_root"
	assert_success
}

@test "emit_cli_compose_files returns layered CLI files in deterministic order" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"

	mkdir -p "$compose_dir"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=codex" > "$test_root/$AGB_PROJECT_DIR/active-target.env"

	touch "$compose_dir/base.yml"
	touch "$compose_dir/agent.codex.yml"
	touch "$compose_dir/user.override.yml"
	touch "$compose_dir/user.agent.codex.override.yml"

	run emit_cli_compose_files "$test_root"
	assert_success
	assert_line --index 0 "$compose_dir/base.yml"
	assert_line --index 1 "$compose_dir/agent.codex.yml"
	assert_line --index 2 "$compose_dir/user.override.yml"
	assert_line --index 3 "$compose_dir/user.agent.codex.override.yml"
}
