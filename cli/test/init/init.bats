#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/init
	source "$AGB_LIBEXECDIR/init/init"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"

	local bin_dir="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin_dir"
	cat > "$bin_dir/yq" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$bin_dir/yq"
	PATH="$bin_dir:$PATH"
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

	run init --batch --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init accepts valid --ide value for devcontainer mode" {
	stub policy "$PROJECT_DIR/.agent-sandbox/policy-devcontainer-copilot.yaml copilot jetbrains : :"
	stub devcontainer "--policy-file .agent-sandbox/policy-devcontainer-copilot.yaml --project-path $PROJECT_DIR --agent copilot --ide jetbrains --name test : :"

	run init --batch --agent copilot --mode devcontainer --ide jetbrains --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init requires --agent in batch mode" {
	run init --batch --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Missing required option in batch mode: --agent"
}

@test "init requires --mode in batch mode" {
	run init --batch --agent claude --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Missing required option in batch mode: --mode"
}

@test "init requires --ide in batch mode for devcontainer mode" {
	run init --batch --agent claude --mode devcontainer --path "$PROJECT_DIR"
	assert_failure
	assert_output --partial "Missing required option in batch mode: --ide"
}

@test "init opens generated files for review by default when flags are provided" {
	unset -f select_yes_no
	unset -f open_editor

	local policy_path="$PROJECT_DIR/.agent-sandbox/policy-cli-claude.yaml"
	local compose_path="$PROJECT_DIR/.agent-sandbox/docker-compose.yml"

	stub select_yes_no \
		"'Review the generated policy file at $policy_path?' : echo true" \
		"'Review the generated compose file at $compose_path?' : echo true"
	stub open_editor \
		"$policy_path : :" \
		"$compose_path : :"
	stub policy "$policy_path claude : :"
	stub cli "--policy-file .agent-sandbox/policy-cli-claude.yaml --project-path $PROJECT_DIR --agent claude --name test : :"

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init warns and continues when editor cannot be opened" {
	unset -f select_yes_no
	unset -f open_editor

	local policy_path="$PROJECT_DIR/.agent-sandbox/policy-cli-claude.yaml"
	local compose_path="$PROJECT_DIR/.agent-sandbox/docker-compose.yml"

	stub select_yes_no \
		"'Review the generated policy file at $policy_path?' : echo true" \
		"'Review the generated compose file at $compose_path?' : echo false"
	stub open_editor \
		"$policy_path : exit 1"
	stub policy "$policy_path claude : :"
	stub cli "--policy-file .agent-sandbox/policy-cli-claude.yaml --project-path $PROJECT_DIR --agent claude --name test : :"

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
	assert_output --partial "Could not open editor for $policy_path. Review it manually."
}

@test "init skips review prompts in batch mode" {
	unset -f select_yes_no
	unset -f open_editor

	stub policy "$PROJECT_DIR/.agent-sandbox/policy-cli-claude.yaml claude : :"
	stub cli "--policy-file .agent-sandbox/policy-cli-claude.yaml --project-path $PROJECT_DIR --agent claude --name test : :"

	run init --batch --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
}

@test "init interactive flow (cli mode)" {
	unset -f read_line
	unset -f select_option
	unset -f select_yes_no

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox
	local policy_file=".agent-sandbox/policy-cli-claude.yaml"

	stub read_line "'Project name [$expected_default]:' : echo my-interactive-project"
	stub select_option \
		"'Select agent:' claude copilot codex : echo claude" \
		"'Select mode:' cli devcontainer : echo cli"
	stub select_yes_no \
		"'Review the generated policy file at $PROJECT_DIR/$policy_file?' : echo false" \
		"'Review the generated compose file at $PROJECT_DIR/.agent-sandbox/docker-compose.yml?' : echo false"

	stub policy "$PROJECT_DIR/$policy_file claude : :"
	stub cli "--policy-file $policy_file --project-path $PROJECT_DIR --agent claude --name my-interactive-project : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init interactive flow (devcontainer mode, default name)" {
	unset -f read_line
	unset -f select_option
	unset -f select_yes_no

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox
	local policy_file=".agent-sandbox/policy-devcontainer-copilot.yaml"

	stub read_line "'Project name [$expected_default]:' : echo ''"
	stub select_option \
		"'Select agent:' claude copilot codex : echo copilot" \
		"'Select mode:' cli devcontainer : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"
	stub select_yes_no \
		"'Review the generated policy file at $PROJECT_DIR/$policy_file?' : echo false" \
		"'Review the generated compose file at $PROJECT_DIR/.devcontainer/docker-compose.yml?' : echo false"

	local expected_name
	expected_name=$(basename "$PROJECT_DIR")-sandbox-devcontainer

	stub policy "$PROJECT_DIR/$policy_file copilot vscode : :"
	stub devcontainer "--policy-file $policy_file --project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init interactive flow (devcontainer mode, custom name)" {
	unset -f read_line
	unset -f select_option
	unset -f select_yes_no

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox
	local policy_file=".agent-sandbox/policy-devcontainer-copilot.yaml"

	stub read_line "'Project name [$expected_default]:' : echo foo"
	stub select_option \
		"'Select agent:' claude copilot codex : echo copilot" \
		"'Select mode:' cli devcontainer : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"
	stub select_yes_no \
		"'Review the generated policy file at $PROJECT_DIR/$policy_file?' : echo false" \
		"'Review the generated compose file at $PROJECT_DIR/.devcontainer/docker-compose.yml?' : echo false"

	local expected_name="foo-devcontainer"

	stub policy "$PROJECT_DIR/$policy_file copilot vscode : :"
	stub devcontainer "--policy-file $policy_file --project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init with --mode flag applies suffix to interactive name" {
	unset -f read_line
	unset -f select_option
	unset -f select_yes_no

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox
	local policy_file=".agent-sandbox/policy-devcontainer-copilot.yaml"

	stub read_line "'Project name [$expected_default]:' : echo baz"
	stub select_option \
		"'Select agent:' claude copilot codex : echo copilot" \
		"'Select IDE:' vscode jetbrains none : echo vscode"
	stub select_yes_no \
		"'Review the generated policy file at $PROJECT_DIR/$policy_file?' : echo false" \
		"'Review the generated compose file at $PROJECT_DIR/.devcontainer/docker-compose.yml?' : echo false"

	local expected_name="baz-devcontainer"

	stub policy "$PROJECT_DIR/$policy_file copilot vscode : :"
	stub devcontainer "--policy-file $policy_file --project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --mode devcontainer --path "$PROJECT_DIR"

	assert_success
}
