#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/destroy/destroy
	source "$AGB_LIBEXECDIR/destroy/destroy"
}

teardown() {
	unstub_all
}

@test "destroy removes project directory from repo root" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy removes devcontainer directory if present" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/.devcontainer" ]]
	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy works when only devcontainer exists" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/.devcontainer/docker-compose.yml"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/.devcontainer" ]]
}

@test "destroy works from nested directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/nested/deep"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root/nested/deep"
	destroy -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy aborts when user answers no" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	cd "$test_root"
	run destroy <<<"n"

	assert_output --partial "Aborting"
	[[ -d "$test_root/$AGB_PROJECT_DIR" ]]
}
