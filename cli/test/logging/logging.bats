#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/logging.bash
	source "$AGB_LIBDIR/logging.bash"
}

teardown() {
	unstub_all
}

@test "debug writes to stderr with DEBUG tag" {
	run bash -c 'source "$AGB_LIBDIR/logging.bash"; echo "test message" | debug'
	assert_success
	assert_output --partial "[DEBUG]"
	assert_output --partial "test message"
}

@test "info writes to stderr with INFO tag" {
	run bash -c 'source "$AGB_LIBDIR/logging.bash"; echo "test message" | info'
	assert_success
	assert_output --partial "[INFO]"
	assert_output --partial "test message"
}

@test "warning writes to stderr with WARN tag" {
	run bash -c 'source "$AGB_LIBDIR/logging.bash"; echo "test message" | warning'
	assert_success
	assert_output --partial "[WARN]"
	assert_output --partial "test message"
}

@test "error writes to stderr with ERROR tag" {
	run bash -c 'source "$AGB_LIBDIR/logging.bash"; echo "test message" | error'
	assert_success
	assert_output --partial "[ERROR]"
	assert_output --partial "test message"
}

@test "logging functions include timestamp" {
	run bash -c 'source "$AGB_LIBDIR/logging.bash"; echo "hello" | info'
	assert_success
	# Timestamp format is HH:MM:SS
	assert_output --regexp '[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "logging works when tput is unavailable" {
	run bash -c '
		tput() { :; }
		export -f tput
		source "$AGB_LIBDIR/logging.bash"
		echo "fallback test" | info
	'
	assert_success
	assert_output --partial "[INFO]"
	assert_output --partial "fallback test"
}
