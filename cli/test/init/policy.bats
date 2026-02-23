#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/policy
	source "$AGB_LIBEXECDIR/init/policy"
}

teardown() {
	unstub_all
}

@test "policy creates policy file from template" {
	local policy_file="$BATS_TEST_TMPDIR/policy.yaml"

	run policy "$policy_file" "github"
	assert_success

	# File should exist
	[[ -f "$policy_file" ]]

	# Should contain the service
	run yq '.services[0]' "$policy_file"
	assert_output "github"
}

@test "policy creates parent directories" {
	local policy_file="$BATS_TEST_TMPDIR/nested/deep/policy.yaml"

	run policy "$policy_file" "github"
	assert_success

	[[ -f "$policy_file" ]]
}

@test "policy handles multiple services" {
	local policy_file="$BATS_TEST_TMPDIR/policy.yaml"

	run policy "$policy_file" "github" "claude" "vscode"
	assert_success

	run yq '.services | length' "$policy_file"
	assert_output "3"

	run yq '.services[0]' "$policy_file"
	assert_output "github"

	run yq '.services[1]' "$policy_file"
	assert_output "claude"

	run yq '.services[2]' "$policy_file"
	assert_output "vscode"
}

@test "policy preserves domains key from template" {
	local policy_file="$BATS_TEST_TMPDIR/policy.yaml"

	run policy "$policy_file" "github"
	assert_success

	run yq '.domains | length' "$policy_file"
	assert_output "0"
}

@test "policy outputs info message" {
	local policy_file="$BATS_TEST_TMPDIR/policy.yaml"

	run policy "$policy_file" "github"
	assert_success
	assert_output --partial "Policy file created at:"
	assert_output --partial "$policy_file"
}
