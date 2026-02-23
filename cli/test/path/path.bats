#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/path.bash
	source "$AGB_LIBDIR/path.bash"
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
