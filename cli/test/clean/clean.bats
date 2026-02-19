#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/clean/clean
	source "$AGB_LIBEXECDIR/clean/clean"
}

teardown() {
	unstub_all
}

@test "clean removes project directory from repo root" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	clean -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "clean removes devcontainer directory if present" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	clean -f

	[[ ! -d "$test_root/.devcontainer" ]]
	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "clean works when only devcontainer exists" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/.devcontainer/docker-compose.yml"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	clean -f

	[[ ! -d "$test_root/.devcontainer" ]]
}

@test "clean works from nested directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/nested/deep"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root/nested/deep"
	clean -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "clean aborts when user answers no" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	cd "$test_root"
	run clean <<<"n"

	assert_output --partial "Aborting"
	[[ -d "$test_root/$AGB_PROJECT_DIR" ]]
}
