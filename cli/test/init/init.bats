#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/init
	source "$AGB_LIBEXECDIR/init/init"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"
}

teardown() {
	unstub_all
}

@test "init rejects invalid --agent value" {
	run init --name my-project --agent "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid agent: invalid (expected: claude copilot codex)"
}

@test "init rejects invalid --mode value" {
	run init --name my-project --agent claude --mode "invalid" --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid mode: invalid (expected: cli devcontainer)"
}

@test "init rejects invalid --ide value" {
	run init --agent claude --mode devcontainer --ide "invalid" --name test --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Invalid IDE: invalid (expected: vscode jetbrains none)"
}

@test "init accepts valid --agent and --mode values" {
	stub policy "$PROJECT_DIR/.agent-sandbox/policy-cli-claude.yaml claude : :"
	stub cli "--policy-file .agent-sandbox/policy-cli-claude.yaml --project-path $PROJECT_DIR --agent claude --name test : :"

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init accepts valid --ide value for devcontainer mode" {
	stub policy "$PROJECT_DIR/.agent-sandbox/policy-devcontainer-copilot.yaml copilot jetbrains : :"
	stub devcontainer "--policy-file .agent-sandbox/policy-devcontainer-copilot.yaml --project-path $PROJECT_DIR --agent copilot --ide jetbrains --name test : :"

	run init --agent copilot --mode devcontainer --ide jetbrains --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init interactive flow (cli mode)" {
	unset -f read_line
	unset -f select_option

	stub read_line "'Project name [empty for default]:' : echo my-interactive-project"
	stub select_option \
		"'Select agent:' claude copilot codex : echo claude" \
		"'Select mode:' cli devcontainer : echo cli"

	local policy_file=".agent-sandbox/policy-cli-claude.yaml"
	stub policy "$PROJECT_DIR/$policy_file claude : :"
	stub cli "--policy-file $policy_file --project-path $PROJECT_DIR --agent claude --name my-interactive-project : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init interactive flow (devcontainer mode)" {
	unset -f read_line
	unset -f select_option

	stub read_line "'Project name [empty for default]:' : echo ''"
	stub select_option \
		"'Select agent:' claude copilot codex : echo copilot" \
		"'Select mode:' cli devcontainer : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"

	local expected_name
	expected_name=$(basename "$PROJECT_DIR")-sandbox-devcontainer
	local policy_file=".agent-sandbox/policy-devcontainer-copilot.yaml"

	stub policy "$PROJECT_DIR/$policy_file copilot vscode : :"
	stub devcontainer "--policy-file $policy_file --project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}
