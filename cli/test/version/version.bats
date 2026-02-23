#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/version/version
	source "$AGB_ROOT/libexec/version/version"

	export AGB_ROOT
}

teardown() {
	unstub_all
}

@test "version reads from .version file when it exists" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo"
	echo "1.2.3" > "$repo/.version"

	run version "TestApp" "$repo"
	assert_success
	assert_output --partial "[INFO]"
	assert_output --partial "TestApp 1.2.3"
}

@test "version uses git when no .version file exists" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo"

	stub git \
		"-C $repo log -n1 --date=format:%Y%m%d.%H%M%S --format=%cd : echo 20250101.120000" \
		"-C $repo describe --abbrev=7 --dirty --always --tags : echo abc1234"

	run version "TestApp" "$repo"
	assert_success
	assert_output --partial "[INFO]"
	assert_output --partial "TestApp 20250101.120000-abc1234"
}

@test "version warns when no .version and no git" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo"

	# Create a minimal PATH without git
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
	mkdir -p "$fake_bin"
	for cmd in bash date tput cat tr; do
		local real
		real=$(command -v "$cmd" 2>/dev/null) || true
		[[ -n "$real" ]] && ln -sf "$real" "$fake_bin/$cmd"
	done

	run env PATH="$fake_bin" bash -c "
		source '$AGB_LIBDIR/logging.bash'
		source '$AGB_ROOT/libexec/version/version'
		version 'TestApp' '$repo'
	"
	assert_success
	assert_output --partial "[WARN]"
	assert_output --partial "git not found"
}

@test "version uses custom name argument" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo"
	echo "0.1.0" > "$repo/.version"

	run version "My Tool" "$repo"
	assert_success
	assert_output --partial "My Tool 0.1.0"
}

@test "version uses default name when no argument" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo"
	echo "2.0.0" > "$repo/.version"

	export AGB_ROOT="$repo"
	run version
	assert_success
	assert_output --partial "Agent Sandbox 2.0.0"
}
