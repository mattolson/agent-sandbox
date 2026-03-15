#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/policy
	source "$AGB_LIBEXECDIR/init/policy"
	# shellcheck source=../../lib/policyfile.bash
	source "$AGB_LIBDIR/policyfile.bash"
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

@test "policy creates file without output" {
	local policy_file="$BATS_TEST_TMPDIR/policy.yaml"

	run policy "$policy_file" "github"
	assert_success
	assert_output ""
}

@test "scaffold_user_policy_file_if_missing creates layered user policy scaffold" {
	local policy_file="$BATS_TEST_TMPDIR/user.policy.yaml"

	run scaffold_user_policy_file_if_missing "$policy_file" "user.policy.yaml"
	assert_success

	run yq '.services | length' "$policy_file"
	assert_output "0"

	run yq '.domains | length' "$policy_file"
	assert_output "0"
}
