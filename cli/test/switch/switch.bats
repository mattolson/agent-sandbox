#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/switch/switch
	source "$AGB_LIBEXECDIR/switch/switch"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR/.git"
	cd "$PROJECT_DIR"
}

teardown() {
	unstub_all
}

@test "switch writes active agent when --agent is provided" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"

	run switch --agent codex

	assert_success
	assert_output --partial "Active agent set to 'codex'."
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 1 "ACTIVE_AGENT=codex"
}

@test "switch prompts for agent when --agent is omitted" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"
	unset -f select_option
	stub select_option "'Select agent:' claude copilot codex : echo copilot"

	run switch

	assert_success
	assert_output --partial "Active agent set to 'copilot'."
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 1 "ACTIVE_AGENT=copilot"
}

@test "switch rejects invalid --agent value" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"

	run switch --agent invalid

	assert_failure
	assert_output --partial "Invalid agent: invalid (expected: claude copilot codex)"
}

@test "switch is a no-op when agent is already active" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	run switch --agent claude

	assert_success
	assert_output --partial "Active agent is already 'claude'. No changes made."
	run cat "$PROJECT_DIR/.agent-sandbox/active-target.env"
	assert_success
	assert_line --index 1 "ACTIVE_AGENT=claude"
}

@test "switch fails when agent-sandbox is not initialized" {
	run switch --agent claude

	assert_failure
	assert_output --partial "Run 'agentbox init' first."
}
