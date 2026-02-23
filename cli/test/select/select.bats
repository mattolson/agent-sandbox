#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/select.bash
	source "$AGB_LIBDIR/select.bash"
}

teardown() {
	unstub_all
}

@test "select_option returns first option on empty input" {
	run select_option "Pick:" "alpha" "beta" "gamma" <<< ""
	assert_success
	assert_line "alpha"
}

@test "select_option returns selected option by number" {
	run select_option "Pick:" "alpha" "beta" "gamma" <<< "2"
	assert_success
	assert_line "beta"
}

@test "select_option retries on invalid then accepts valid input" {
	input=$'invalid\n3\n'
	run select_option "Pick:" "alpha" "beta" "gamma" <<< "$input"
	assert_success
	assert_line "gamma"
	assert_output --partial "Invalid selection"
}

@test "select_option displays numbered menu" {
	run select_option "Pick:" "alpha" "beta" <<< ""
	assert_success
	assert_output --partial "1) alpha"
	assert_output --partial "2) beta"
}

@test "read_line captures typed input to stdout" {
	run read_line "Name:" <<< "hello world"
	assert_success
	assert_output "hello world"
}

@test "select_yes_no returns true on y" {
	run select_yes_no "Continue?" <<< "y"
	assert_success
	assert_output "true"
}

@test "select_yes_no returns true on Y" {
	run select_yes_no "Continue?" <<< "Y"
	assert_success
	assert_output "true"
}

@test "select_yes_no returns false on n" {
	run select_yes_no "Continue?" <<< "n"
	assert_success
	assert_output "false"
}

@test "select_yes_no returns false on empty input" {
	run select_yes_no "Continue?" <<< ""
	assert_success
	assert_output "false"
}

@test "open_editor returns 1 when editor not found" {
	unset VISUAL

	EDITOR="nonexistent_editor_xyz" run open_editor "/tmp/testfile"
	assert_failure
	assert_output --partial "not found"
}

@test "open_editor uses VISUAL over EDITOR" {
	# Verify VISUAL takes precedence by setting EDITOR to something invalid
	# and VISUAL to something that works
	local mock_editor="$BATS_TEST_TMPDIR/mock-visual"
	cat > "$mock_editor" <<'SCRIPT'
#!/bin/bash
echo "visual-edited $1"
SCRIPT
	chmod +x "$mock_editor"

	local testfile="$BATS_TEST_TMPDIR/testfile.txt"
	touch "$testfile"

	# The function redirects from /dev/tty, which may not exist.
	# Test the precedence logic by checking the editor variable resolution.
	VISUAL="nonexistent_visual_xyz" EDITOR="nonexistent_editor_xyz" run open_editor "$testfile"
	assert_failure
	# Should report the VISUAL editor as not found (proving VISUAL took precedence)
	assert_output --partial "nonexistent_visual_xyz"
}
