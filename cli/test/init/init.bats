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
	assert_output --partial "Invalid agent: invalid (expected: claude codex copilot factory gemini)"
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

@test "init fails fast for legacy layouts before prompting" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"
	touch "$PROJECT_DIR/.agent-sandbox/docker-compose.yml"

	unset -f read_line
	unset -f select_option
	read_line() {
		echo "prompted" > "$BATS_TEST_TMPDIR/read-line.called"
		echo test
	}
	select_option() {
		echo "prompted" > "$BATS_TEST_TMPDIR/select-option.called"
		echo claude
	}

	run init --path "$PROJECT_DIR"

	assert_failure
	assert_output --partial "does not support the legacy single-file layout"
	assert_output --partial ".agent-sandbox/docker-compose.legacy.yml"
	assert_output --partial "docs/upgrades/m8-layered-layout.md"
	[ ! -f "$BATS_TEST_TMPDIR/read-line.called" ]
	[ ! -f "$BATS_TEST_TMPDIR/select-option.called" ]
}

@test "init accepts valid --agent and --mode values" {
	stub cli "--project-path $PROJECT_DIR --agent claude --name test : :"

	run init --batch --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 1 "ACTIVE_AGENT=claude"
	assert_line --index 2 "PROJECT_NAME=test"
}

@test "init accepts valid --ide value for devcontainer mode" {
	stub devcontainer "--project-path $PROJECT_DIR --agent copilot --ide jetbrains --name test : :"

	run init --batch --agent copilot --mode devcontainer --ide jetbrains --name test --path "$PROJECT_DIR"
	assert_success
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 1 "ACTIVE_AGENT=copilot"
	assert_line --index 2 "DEVCONTAINER_IDE=jetbrains"
	assert_line --index 3 "PROJECT_NAME=test"
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

@test "init prints config-viewing commands instead of review prompts" {
	unset -f select_yes_no
	select_yes_no() {
		echo called > "$BATS_TEST_TMPDIR/select-yes-no.called"
		echo false
	}
	stub cli "--project-path $PROJECT_DIR --agent claude --name test : :"

	run init --agent claude --mode cli --name test --path "$PROJECT_DIR"
	assert_success
	assert_output --partial "agentbox policy config"
	assert_output --partial "agentbox compose config"
	[ ! -f "$BATS_TEST_TMPDIR/select-yes-no.called" ]
}

@test "init interactive flow (cli mode)" {
	unset -f read_line
	unset -f select_option

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox

	stub read_line "'Project name [$expected_default]:' : echo my-interactive-project"
	stub select_option \
		"'Select agent:' claude codex copilot gemini : echo claude" \
		"'Select mode:' cli devcontainer : echo cli"

	stub cli "--project-path $PROJECT_DIR --agent claude --name my-interactive-project : :"

	run init --path "$PROJECT_DIR"

	assert_success
	assert_output --partial "agentbox policy config"
	assert_output --partial "agentbox compose config"
}

@test "init interactive flow (devcontainer mode, default name)" {
	unset -f read_line
	unset -f select_option

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox

	stub read_line "'Project name [$expected_default]:' : echo ''"
	stub select_option \
		"'Select agent:' claude codex copilot gemini : echo copilot" \
		"'Select mode:' cli devcontainer : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"

	local expected_name
	expected_name=$(basename "$PROJECT_DIR")-sandbox

	stub devcontainer "--project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init interactive flow (devcontainer mode, custom name)" {
	unset -f read_line
	unset -f select_option

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox

	stub read_line "'Project name [$expected_default]:' : echo foo"
	stub select_option \
		"'Select agent:' claude codex copilot gemini : echo copilot" \
		"'Select mode:' cli devcontainer : echo devcontainer" \
		"'Select IDE:' vscode jetbrains none : echo vscode"

	local expected_name="foo"

	stub devcontainer "--project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --path "$PROJECT_DIR"

	assert_success
}

@test "init with --mode flag preserves the interactive base name" {
	unset -f read_line
	unset -f select_option

	local expected_default
	expected_default=$(basename "$PROJECT_DIR")-sandbox

	stub read_line "'Project name [$expected_default]:' : echo baz"
	stub select_option \
		"'Select agent:' claude codex copilot gemini : echo copilot" \
		"'Select IDE:' vscode jetbrains none : echo vscode"

	local expected_name="baz"

	stub devcontainer "--project-path $PROJECT_DIR --agent copilot --ide vscode --name $expected_name : :"

	run init --mode devcontainer --path "$PROJECT_DIR"

	assert_success
}

@test "init stores the base project name for devcontainer mode" {
	stub devcontainer "--project-path $PROJECT_DIR --agent codex --ide vscode --name already-devcontainer : :"

	run init --batch --agent codex --mode devcontainer --ide vscode --name already-devcontainer --path "$PROJECT_DIR"

	assert_success
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 3 "PROJECT_NAME=already-devcontainer"
}
