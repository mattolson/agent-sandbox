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

@test "switch fails fast for legacy layouts without prompting" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox"
	touch "$PROJECT_DIR/.agent-sandbox/docker-compose.yml"
	printf '%s\n' "services: [claude]" > "$PROJECT_DIR/.agent-sandbox/policy-cli-claude.yaml"

	unset -f select_option
	select_option() {
		echo "prompted" > "$BATS_TEST_TMPDIR/select-agent.called"
		echo codex
	}

	run switch

	assert_failure
	assert_output --partial "does not support the legacy single-file layout"
	assert_output --partial ".agent-sandbox/docker-compose.yml -> .agent-sandbox/docker-compose.legacy.yml"
	assert_output --partial "docs/upgrades/m8-layered-layout.md"
	[ ! -f "$BATS_TEST_TMPDIR/select-agent.called" ]
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

@test "switch refreshes layered runtime files when agent is already active" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox/compose"
	touch "$PROJECT_DIR/.agent-sandbox/compose/base.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	unset -f ensure_cli_agent_runtime_files
	ensure_cli_agent_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	}

	run switch --agent claude

	assert_success
	assert_output --partial "Refreshed layered runtime files."
	run cat "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	assert_success
	assert_output "$PROJECT_DIR claude"
}

@test "switch scaffolds target runtime files for layered CLI projects" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox/compose"
	touch "$PROJECT_DIR/.agent-sandbox/compose/base.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	unset -f ensure_cli_agent_runtime_files
	ensure_cli_agent_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	}

	run switch --agent codex

	assert_success
	run cat "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	assert_success
	assert_output "$PROJECT_DIR codex"
}

@test "switch preserves existing user-owned compose overrides" {
	local compose_dir="$PROJECT_DIR/.agent-sandbox/compose"
	local shared_override="$compose_dir/user.override.yml"
	local active_override="$compose_dir/user.agent.claude.override.yml"
	local target_override="$compose_dir/user.agent.codex.override.yml"

	mkdir -p "$compose_dir"
	touch "$compose_dir/base.yml"
	printf '%s\n' \
		"# shared override" \
		"services:" \
		"  agent:" \
		"    environment:" \
		"      - SHARED=1" > "$shared_override"
	printf '%s\n' \
		"# claude override" \
		"services:" \
		"  agent:" \
		"    environment:" \
		"      - CLAUDE_ONLY=1" > "$active_override"
	printf '%s\n' \
		"# codex override" \
		"services:" \
		"  agent:" \
		"    environment:" \
		"      - CODEX_ONLY=1" > "$target_override"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	ensure_cli_agent_runtime_files() { :; }

	run switch --agent codex

	assert_success
	run cat "$shared_override"
	assert_success
	assert_output --partial "SHARED=1"
	run cat "$active_override"
	assert_success
	assert_output --partial "CLAUDE_ONLY=1"
	run cat "$target_override"
	assert_success
	assert_output --partial "CODEX_ONLY=1"
}

@test "switch preserves shared and agent policy overrides" {
	local compose_dir="$PROJECT_DIR/.agent-sandbox/compose"
	local policy_dir="$PROJECT_DIR/.agent-sandbox/policy"
	local shared_policy="$policy_dir/user.policy.yaml"
	local active_policy="$policy_dir/user.agent.claude.policy.yaml"
	local target_policy="$policy_dir/user.agent.codex.policy.yaml"

	mkdir -p "$compose_dir" "$policy_dir"
	touch "$compose_dir/base.yml"
	printf '%s\n' \
		"services:" \
		"  - github" > "$shared_policy"
	printf '%s\n' \
		"domains:" \
		"  - api.anthropic.com" > "$active_policy"
	printf '%s\n' \
		"domains:" \
		"  - api.openai.com" > "$target_policy"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	ensure_cli_agent_runtime_files() { :; }

	run switch --agent codex

	assert_success
	run cat "$shared_policy"
	assert_success
	assert_output --partial "github"
	run cat "$active_policy"
	assert_success
	assert_output --partial "api.anthropic.com"
	run cat "$target_policy"
	assert_success
	assert_output --partial "api.openai.com"
}

@test "switch does not touch docker while changing the active agent" {
	mkdir -p "$PROJECT_DIR/.agent-sandbox/compose"
	touch "$PROJECT_DIR/.agent-sandbox/compose/base.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent for this project." \
		"ACTIVE_AGENT=claude" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	ensure_cli_agent_runtime_files() { :; }
	docker() {
		echo "$*" > "$BATS_TEST_TMPDIR/docker.called"
		return 1
	}
	export -f docker

	run switch --agent codex

	assert_success
	[ ! -f "$BATS_TEST_TMPDIR/docker.called" ]
}

@test "switch refreshes centralized devcontainer runtime files when agent is already active" {
	mkdir -p "$PROJECT_DIR/.devcontainer" "$PROJECT_DIR/.agent-sandbox/compose"
	touch "$PROJECT_DIR/.devcontainer/devcontainer.json" "$PROJECT_DIR/.agent-sandbox/compose/mode.devcontainer.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=claude" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=project-sandbox" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	unset -f ensure_devcontainer_runtime_files
	ensure_devcontainer_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	}

	run switch --agent claude

	assert_success
	assert_output --partial "Refreshed layered runtime files."
	run cat "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	assert_success
	assert_output "$PROJECT_DIR claude"
}

@test "switch syncs centralized devcontainer runtime files for the target agent" {
	mkdir -p "$PROJECT_DIR/.devcontainer" "$PROJECT_DIR/.agent-sandbox/compose"
	touch "$PROJECT_DIR/.devcontainer/devcontainer.json" "$PROJECT_DIR/.agent-sandbox/compose/mode.devcontainer.yml"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=claude" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=project-sandbox" > "$PROJECT_DIR/.agent-sandbox/active-target.env"

	unset -f ensure_devcontainer_runtime_files
	ensure_devcontainer_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	}

	run switch --agent codex

	assert_success
	run cat "$BATS_TEST_TMPDIR/ensure-devcontainer-runtime-files.args"
	assert_success
	assert_output "$PROJECT_DIR codex"
}

@test "switch fails when agent-sandbox is not initialized" {
	run switch --agent claude

	assert_failure
	assert_output --partial "Run 'agentbox init' first."
}
