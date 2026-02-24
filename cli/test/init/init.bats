#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/init
	source "$AGB_LIBEXECDIR/init/init"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"
}

@test "init rejects invalid --agent value" {
	run init --agent "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid agent: invalid (expected: claude copilot codex)"
}

@test "init rejects invalid --mode value" {
	run init --agent claude --mode "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid mode: invalid (expected: cli devcontainer)"
}

@test "init rejects invalid --ide value" {
	policy() { :; }
	devcontainer() { :; }

	run init --agent claude --mode devcontainer --ide "invalid" --name test --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid IDE: invalid (expected: vscode jetbrains none)"
}

@test "init accepts valid --agent and --mode values" {
	policy() { :; }
	cli() { :; }

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init accepts valid --ide value for devcontainer mode" {
	policy() { :; }
	devcontainer() { :; }

	run init --agent copilot --mode devcontainer --ide jetbrains --name test --path "$PROJECT_DIR"
	assert_success
}
