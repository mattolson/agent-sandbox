#!/usr/bin/env bats

setup() {
	load test_helper
	# shellcheck source=../../libexec/destroy/destroy
	source "$AGB_LIBEXECDIR/destroy/destroy"

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

@test "destroy removes project directory from repo root" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy removes devcontainer directory if present" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/.devcontainer" ]]
	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy works when only devcontainer exists" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/.devcontainer/docker-compose.yml"
	mkdir -p "$test_root/.devcontainer"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/.devcontainer" ]]
}

@test "destroy works from nested directory" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	mkdir -p "$test_root/nested/deep"
	touch "$compose_file"

	stub docker \
		"compose -f $compose_file down --volumes : :"

	cd "$test_root/nested/deep"
	destroy -f

	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy works for centralized devcontainer layout" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_dir="$test_root/$AGB_PROJECT_DIR/compose"
	local base_file="$compose_dir/base.yml"
	local agent_file="$compose_dir/agent.codex.yml"
	local mode_file="$compose_dir/mode.devcontainer.yml"
	local shared_override="$compose_dir/user.override.yml"
	local agent_override="$compose_dir/user.agent.codex.override.yml"

	mkdir -p "$compose_dir" "$test_root/.devcontainer" "$test_root/.git"
	touch \
		"$base_file" \
		"$agent_file" \
		"$mode_file" \
		"$shared_override" \
		"$agent_override" \
		"$test_root/.devcontainer/devcontainer.json"
	printf '%s\n' \
		"# Managed by agentbox. Tracks the active agent and related runtime metadata for this project." \
		"ACTIVE_AGENT=codex" \
		"DEVCONTAINER_IDE=vscode" \
		"PROJECT_NAME=repo-sandbox" > "$test_root/$AGB_PROJECT_DIR/active-target.env"

	stub docker \
		"compose -f $base_file -f $agent_file -f $mode_file -f $shared_override -f $agent_override down --volumes : :"

	cd "$test_root"
	destroy -f

	[[ ! -d "$test_root/.devcontainer" ]]
	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy continues when no compose stack can be resolved" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/$AGB_PROJECT_DIR" "$test_root/.devcontainer" "$test_root/.git"

	cd "$test_root"
	run destroy -f

	assert_success
	assert_output --partial "No compose stack found. Skipping container shutdown."
	[[ ! -d "$test_root/.devcontainer" ]]
	[[ ! -d "$test_root/$AGB_PROJECT_DIR" ]]
}

@test "destroy aborts when user answers no" {
	local test_root="$BATS_TEST_TMPDIR/repo"
	local compose_file="$test_root/$AGB_PROJECT_DIR/docker-compose.yml"
	mkdir -p "$test_root/$AGB_PROJECT_DIR"
	touch "$compose_file"

	cd "$test_root"
	run destroy <<<"n"

	assert_output --partial "Aborting"
	[[ -d "$test_root/$AGB_PROJECT_DIR" ]]
}
