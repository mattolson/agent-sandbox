#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/compat.bash
	source "$AGB_LIBDIR/compat.bash"
}

@test "mapfile reads single line into array" {
	local -a result
	mapfile -t result < <(echo "single line")

	assert_equal "${#result[@]}" 1
	assert_equal "${result[0]}" "single line"
}

@test "mapfile reads multiple lines into array" {
	local -a result
	mapfile -t result < <(printf "line1\nline2\nline3\n")

	assert_equal "${#result[@]}" 3
	assert_equal "${result[0]}" "line1"
	assert_equal "${result[1]}" "line2"
	assert_equal "${result[2]}" "line3"
}

@test "mapfile handles empty input" {
	local -a result=()
	mapfile -t result < <(echo -n "")

	assert_equal "${#result[@]}" 0
}

@test "mapfile works with process substitution" {
	local -a result
	mapfile -t result < <(printf "line1\nline2\n")

	assert_equal "${#result[@]}" 2
	assert_equal "${result[0]}" "line1"
	assert_equal "${result[1]}" "line2"
}

@test "mapfile works with here-string" {
	local -a result
	local input="line1
line2
line3"
	mapfile -t result <<<"$input"

	assert_equal "${#result[@]}" 3
	assert_equal "${result[0]}" "line1"
	assert_equal "${result[1]}" "line2"
	assert_equal "${result[2]}" "line3"
}

@test "mapfile preserves spaces in lines" {
	local -a result
	mapfile -t result < <(printf "  leading spaces\ntrailing spaces  \n  both  \n")

	assert_equal "${#result[@]}" 3
	assert_equal "${result[0]}" "  leading spaces"
	assert_equal "${result[1]}" "trailing spaces  "
	assert_equal "${result[2]}" "  both  "
}

@test "mapfile handles lines with special characters" {
	local -a result
	#shellcheck disable=SC2016
	mapfile -t result < <(printf 'line with $var\nline with "quotes"\nline with \\backslash\n')

	assert_equal "${#result[@]}" 3
	#shellcheck disable=SC2016
	assert_equal "${result[0]}" 'line with $var'
	assert_equal "${result[1]}" 'line with "quotes"'
	assert_equal "${result[2]}" 'line with \backslash'
}

@test "mapfile handles empty lines" {
	local -a result
	mapfile -t result < <(printf "line1\n\nline3\n")

	assert_equal "${#result[@]}" 3
	assert_equal "${result[0]}" "line1"
	assert_equal "${result[1]}" ""
	assert_equal "${result[2]}" "line3"
}

@test "mapfile requires -t flag" {
	local -a result
	run mapfile result < <(echo "test")

	assert_failure
	assert_output --partial "mapfile: -t flag is required"
}

@test "mapfile works with set -e" {
	run bash -ec '
        export BATS_VERSION="1.5.0"
        source "'"$AGB_LIBDIR"'/compat.bash"

        test_mapfile() {
            local -a result
            mapfile -t result < <(printf "line1\nline2\n")

            echo "${#result[@]}"
            printf "%s\n" "${result[@]}"
        }

        test_mapfile
    '

	assert_success
	assert_line --index 0 "2"
	assert_line --index 1 "line1"
	assert_line --index 2 "line2"
}

@test "mapfile handles long input" {
	local -a result
	mapfile -t result < <(seq 1 100 | while read -r i; do echo "line $i"; done)

	assert_equal "${#result[@]}" 100
	assert_equal "${result[0]}" "line 1"
	assert_equal "${result[99]}" "line 100"
}

@test "mapfile strips trailing newlines with -t flag" {
	local -a result
	# Note: -t flag should strip trailing newlines (which read -r already does)
	mapfile -t result < <(printf "line1\nline2\n")

	# Verify no trailing empty elements
	assert_equal "${#result[@]}" 2
	assert_equal "${result[0]}" "line1"
	assert_equal "${result[1]}" "line2"
}
