#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../lib/devcontainer.bash
	source "$AGB_LIBDIR/devcontainer.bash"

	REPO_ROOT="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$REPO_ROOT/.git" "$REPO_ROOT/.devcontainer"
}

teardown() {
	unstub_all
}

@test "render_devcontainer_json appends user extension arrays instead of replacing template arrays" {
	local user_file="$REPO_ROOT/.devcontainer/devcontainer.user.json"
	local output_file="$REPO_ROOT/.devcontainer/devcontainer.json"

	cat >"$user_file" <<'JSON'
{
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python"
      ]
    }
  }
}
JSON

	render_devcontainer_json "$REPO_ROOT" "claude" "$output_file"

	run yq -r '.customizations.vscode.extensions[0]' "$output_file"
	assert_success
	assert_output "anthropic.claude-code"

	run yq -r '.customizations.vscode.extensions[1]' "$output_file"
	assert_success
	assert_output "ms-python.python"
}
