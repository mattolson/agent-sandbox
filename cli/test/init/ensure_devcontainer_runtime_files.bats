#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/devcontainer.bash
	source "$AGB_LIBDIR/devcontainer.bash"

	REPO_ROOT="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$REPO_ROOT/.git" "$REPO_ROOT/$AGB_PROJECT_DIR/compose"
}

teardown() {
	unstub_all
}

@test "ensure_devcontainer_runtime_files skips agent compose resync after creating the agent layer" {
	local compose_dir="$REPO_ROOT/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"

	touch "$base_file"

	unset -f read_devcontainer_ide
	read_devcontainer_ide() { echo vscode; }
	unset -f read_project_name
	read_project_name() { echo repo-sandbox; }
	unset -f read_compose_service_image_if_exists
	read_compose_service_image_if_exists() { return 1; }
	unset -f set_devcontainer_override_defaults_for_ide
	set_devcontainer_override_defaults_for_ide() { :; }
	unset -f set_project_name
	set_project_name() { :; }
	unset -f write_cli_agent_compose_file
	write_cli_agent_compose_file() { touch "$agent_file"; }
	unset -f ensure_cli_agent_runtime_files
	ensure_cli_agent_runtime_files() {
		printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	}
	unset -f scaffold_devcontainer_user_json_if_missing
	scaffold_devcontainer_user_json_if_missing() { :; }
	unset -f render_devcontainer_json
	render_devcontainer_json() { :; }
	unset -f write_devcontainer_mode_compose_file
	write_devcontainer_mode_compose_file() { :; }
	unset -f write_devcontainer_policy_file
	write_devcontainer_policy_file() { :; }
	unset -f cleanup_legacy_devcontainer_managed_files
	cleanup_legacy_devcontainer_managed_files() { :; }
	unset -f write_devcontainer_state
	write_devcontainer_state() { :; }

	run ensure_devcontainer_runtime_files "$REPO_ROOT" codex

	assert_success
	run cat "$BATS_TEST_TMPDIR/ensure-cli-agent-runtime-files.args"
	assert_success
	assert_output "$REPO_ROOT codex true"
}
