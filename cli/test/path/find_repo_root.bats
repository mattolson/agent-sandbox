#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/path.bash
	source "$AGB_LIBDIR/path.bash"
}

teardown() {
	unstub_all
}

@test "finds root with .git directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/.git"
	mkdir -p "$test_root/nested/deep"

	run find_repo_root "$test_root/nested/deep"
	assert_success
	assert_output "$test_root"
}

@test "finds root with .devcontainer directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/.devcontainer"
	mkdir -p "$test_root/nested/deep"

	run find_repo_root "$test_root/nested/deep"
	assert_success
	assert_output "$test_root"
}

@test "finds root with \$AGB_PROJECT_DIR directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"

	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/nested/deep"

	run find_repo_root "$test_root/nested/deep"
	assert_success
	assert_output "$test_root"
}

@test "prefers \$AGB_PROJECT_DIR over .git" {
	local test_root="$BATS_TEST_TMPDIR/repo"

	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/.git"
	mkdir -p "$test_root/nested"

	run find_repo_root "$test_root/nested"
	assert_success
	assert_output "$test_root"
}

@test "uses current directory when no argument provided" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/.git"

	cd "$test_root"
	run find_repo_root
	assert_success
	assert_output "$test_root"
}

@test "fails when reaching filesystem root" {
	run find_repo_root "$BATS_TEST_TMPDIR"
	assert_failure
	assert_output --partial "repository root not found"
}

@test "finds root from immediate subdirectory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/.git"
	mkdir -p "$test_root/subdir"

	run find_repo_root "$test_root/subdir"
	assert_success
	assert_output "$test_root"
}

@test "finds root from deeply nested directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/.devcontainer"
	mkdir -p "$test_root/a/b/c/d/e"

	run find_repo_root "$test_root/a/b/c/d/e"
	assert_success
	assert_output "$test_root"
}
