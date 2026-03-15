#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

setup() {
	load test_helper
	# shellcheck source=../../libexec/init/init
	source "$AGB_LIBEXECDIR/init/init"
	# shellcheck source=../../libexec/init/cli
	source "$AGB_LIBEXECDIR/init/cli"
	# shellcheck source=../../libexec/init/devcontainer
	source "$AGB_LIBEXECDIR/init/devcontainer"

	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"
}

teardown() {
	unstub_all
}

render_effective_compose() {
	local output_file=$1
	shift
	local -a compose_args=()
	local compose_file=""

	for compose_file in "$@"
	do
		compose_args+=(-f "$compose_file")
	done

	docker compose "${compose_args[@]}" config --no-interpolate > "$output_file"
}

render_cli_effective_compose() {
	local repo_root=$1
	local agent=$2
	local output_file=$3
	local compose_file=""
	local -a compose_files=()

	while IFS= read -r compose_file
	do
		compose_files+=("$compose_file")
	done < <(emit_cli_compose_files "$repo_root" "$agent")

	render_effective_compose "$output_file" "${compose_files[@]}"
}

render_devcontainer_effective_compose() {
	local repo_root=$1
	local output_file=$2
	local compose_file=""
	local -a compose_files=()

	while IFS= read -r compose_file
	do
		compose_files+=("$compose_file")
	done < <(emit_devcontainer_compose_files "$repo_root")

	render_effective_compose "$output_file" "${compose_files[@]}"
}

assert_env_var() {
	local compose_file=$1
	local service=$2
	local key=$3
	local expected=$4
	local env_type=""
	local actual=""
	local line=""

	run yq -r ".services.$service.environment | type" "$compose_file"
	assert_success
	env_type="$output"

	case "$env_type" in
	"!!map")
		run yq -r ".services.$service.environment.$key" "$compose_file"
		assert_output "$expected"
		;;
	"!!seq")
		run yq -r ".services.$service.environment[]" "$compose_file"
		assert_success

		while IFS= read -r line
		do
			if [[ "$line" == "$key="* ]]
			then
				actual="${line#"$key="}"
				break
			fi
		done <<< "$output"

		assert_equal "$actual" "$expected"
		;;
	*)
		echo "Unexpected environment node type for service '$service': $env_type" >&2
		return 1
		;;
	esac
}

assert_named_volume_declared() {
	local compose_file=$1
	local volume_name=$2

	run env volume_name="$volume_name" yq -e '.volumes | has(env(volume_name))' "$compose_file"
	assert_success
}

assert_bind_mount_suffix() {
	local compose_file=$1
	local service=$2
	local target=$3
	local suffix=$4
	local source_path=""
	local volume_entry=""

	run env target="$target" yq -r \
		".services.$service.volumes[] | select(type == \"!!map\" and .target == env(target)) | .source" \
		"$compose_file"
	assert_success

	while IFS= read -r source_path
	do
		if [[ -n "$source_path" ]] && [[ "$source_path" == *"$suffix" ]]
		then
			return 0
		fi
	done <<< "$output"

	run yq -r ".services.$service.volumes[] | select(type == \"!!str\")" "$compose_file"
	assert_success

	while IFS= read -r volume_entry
	do
		if [[ -z "$volume_entry" ]]
		then
			continue
		fi

		if [[ "$volume_entry" == *":$target" ]] || [[ "$volume_entry" == *":$target:"* ]]
		then
			source_path="${volume_entry%%:$target*}"
			if [[ "$source_path" == *"$suffix" ]]
			then
				return 0
			fi
		fi
	done <<< "$output"

	echo "Expected mount for service '$service' target '$target' to end with '$suffix'." >&2
	echo "Sources found:" >&2
	printf '%s\n' "$output" >&2
	return 1
}

assert_named_volume_mount() {
	local compose_file=$1
	local service=$2
	local source=$3
	local target=$4

	run env source="$source" target="$target" yq -e \
		".services.$service.volumes[] | select(.type == \"volume\" and .source == env(source) and .target == env(target))" \
		"$compose_file"
	assert_success
}

assert_no_mount_target() {
	local compose_file=$1
	local service=$2
	local target=$3

	run yq -r ".services.$service.volumes[] | select(.target == \"$target\") | .target" "$compose_file"
	assert_output ""
}

assert_common_rendered_config() {
	local compose_file=$1
	local expected_proxy_image=$2
	local expected_agent_image=$3

	run yq -r '.services.proxy.image' "$compose_file"
	assert_output "$expected_proxy_image"
	run yq -r '.services.agent.image' "$compose_file"
	assert_output "$expected_agent_image"
	run yq -r '.services.agent.working_dir' "$compose_file"
	assert_output "/workspace"

	assert_env_var "$compose_file" "agent" "HTTP_PROXY" "http://proxy:8080"
	assert_env_var "$compose_file" "agent" "HTTPS_PROXY" "http://proxy:8080"
	assert_env_var "$compose_file" "agent" "NO_PROXY" "localhost,127.0.0.1,proxy"
	assert_env_var "$compose_file" "agent" "GODEBUG" "http2client=0"

	run yq -e '.services.agent.cap_drop[] | select(. == "ALL")' "$compose_file"
	assert_success
	run yq -e '.services.proxy.cap_drop[] | select(. == "ALL")' "$compose_file"
	assert_success

	assert_bind_mount_suffix "$compose_file" "agent" "/workspace" "/project"
	assert_bind_mount_suffix "$compose_file" "agent" "/workspace/.agent-sandbox" "/project/.agent-sandbox"
	assert_named_volume_mount "$compose_file" "agent" "proxy-ca" "/etc/mitmproxy"
	assert_bind_mount_suffix "$compose_file" "proxy" "/etc/agent-sandbox/policy/user.policy.yaml" "/project/.agent-sandbox/policy/user.policy.yaml"

	assert_named_volume_declared "$compose_file" "proxy-state"
	assert_named_volume_declared "$compose_file" "proxy-ca"
}

assert_common_optional_override_mounts() {
	local compose_file=$1

	assert_bind_mount_suffix "$compose_file" "agent" "/home/dev/.config/agent-sandbox/shell.d" "/.config/agent-sandbox/shell.d"
	assert_bind_mount_suffix "$compose_file" "agent" "/home/dev/.dotfiles" "/.config/agent-sandbox/dotfiles"
	assert_bind_mount_suffix "$compose_file" "agent" "/workspace/.git" "/project/.git"
}

assert_shared_policy_scaffold() {
	local policy_file=$1

	assert [ -f "$policy_file" ]
	run yq '.services | length' "$policy_file"
	assert_output "0"
	run yq '.domains | length' "$policy_file"
	assert_output "0"
}

assert_devcontainer_managed_policy_file() {
	local policy_file=$1
	local ide=$2

	assert [ -f "$policy_file" ]
	run yq '.domains | length' "$policy_file"
	assert_output "0"

	case "$ide" in
	vscode | jetbrains)
		run yq '.services | length' "$policy_file"
		assert_output "1"
		yq -e '.services[] | select(. == "'"$ide"'")' "$policy_file"
		;;
	none)
		run yq '.services | length' "$policy_file"
		assert_output "0"
		;;
	esac
}

assert_devcontainer_user_json_file() {
	local json_file=$1

	assert [ -f "$json_file" ]
	run yq 'keys | length' "$json_file"
	assert_output "0"
}

assert_devcontainer_json_file() {
	local json_file=$1
	local agent=$2

	assert [ -f "$json_file" ]
	run yq -r '.dockerComposeFile[0]' "$json_file"
	assert_output "../.agent-sandbox/compose/base.yml"
	run yq -r '.dockerComposeFile[1]' "$json_file"
	assert_output "../.agent-sandbox/compose/agent.$agent.yml"
	run yq -r '.dockerComposeFile[2]' "$json_file"
	assert_output "../.agent-sandbox/compose/mode.devcontainer.yml"
	run yq -r '.dockerComposeFile[3]' "$json_file"
	assert_output "../.agent-sandbox/compose/user.override.yml"
	run yq -r '.dockerComposeFile[4]' "$json_file"
	assert_output "../.agent-sandbox/compose/user.agent.$agent.override.yml"
	run yq -r '.service' "$json_file"
	assert_output "agent"
}

@test "cli init renders the effective claude compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export AGENTBOX_MOUNT_CLAUDE_CONFIG="true"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run init --batch --agent claude --mode cli --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/claude-cli.rendered.yml"
	render_cli_effective_compose "$PROJECT_DIR" "claude" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-claude@sha256:def456"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.claude.policy.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "claude-state" "/home/dev/.claude"
	assert_named_volume_mount "$rendered_file" "agent" "claude-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/home/dev/.claude/CLAUDE.md" "/.claude/CLAUDE.md"
	assert_bind_mount_suffix "$rendered_file" "agent" "/home/dev/.claude/settings.json" "/.claude/settings.json"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.idea" "/project/.idea"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.vscode" "/project/.vscode"
	assert_env_var "$rendered_file" "agent" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "1"

	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.claude.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.claude.override.yml" ]
}

@test "devcontainer init renders the effective claude compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-claude:latest"
	export AGENTBOX_MOUNT_CLAUDE_CONFIG="true"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-claude:latest : echo 'ghcr.io/mattolson/agent-sandbox-claude@sha256:def456'"

	run init --batch --agent claude --mode devcontainer --ide jetbrains --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/claude-devcontainer.rendered.yml"
	render_devcontainer_effective_compose "$PROJECT_DIR" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-claude@sha256:def456"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.claude.policy.yaml"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/devcontainer.policy.yaml" "/project/.agent-sandbox/policy/policy.devcontainer.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "claude-state" "/home/dev/.claude"
	assert_named_volume_mount "$rendered_file" "agent" "claude-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/home/dev/.claude/CLAUDE.md" "/.claude/CLAUDE.md"
	assert_bind_mount_suffix "$rendered_file" "agent" "/home/dev/.claude/settings.json" "/.claude/settings.json"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.devcontainer" "/project/.devcontainer"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.idea" "/project/.idea"
	assert_no_mount_target "$rendered_file" "agent" "/workspace/.vscode"
	yq -e '.services.agent.cap_add[] | select(. == "DAC_OVERRIDE")' "$rendered_file"
	yq -e '.services.agent.cap_add[] | select(. == "CHOWN")' "$rendered_file"
	yq -e '.services.agent.cap_add[] | select(. == "FOWNER")' "$rendered_file"
	assert_env_var "$rendered_file" "agent" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "1"

	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "claude"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "jetbrains"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.claude.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.claude.override.yml" ]
}

@test "cli init renders the effective copilot compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run init --batch --agent copilot --mode cli --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/copilot-cli.rendered.yml"
	render_cli_effective_compose "$PROJECT_DIR" "copilot" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.copilot.policy.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "copilot-state" "/home/dev/.copilot"
	assert_named_volume_mount "$rendered_file" "agent" "copilot-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.idea" "/project/.idea"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.vscode" "/project/.vscode"

	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.copilot.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.copilot.override.yml" ]
}

@test "devcontainer init renders the effective copilot compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-copilot:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-copilot:latest : echo 'ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789'"

	run init --batch --agent copilot --mode devcontainer --ide vscode --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/copilot-devcontainer.rendered.yml"
	render_devcontainer_effective_compose "$PROJECT_DIR" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-copilot@sha256:ghi789"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.copilot.policy.yaml"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/devcontainer.policy.yaml" "/project/.agent-sandbox/policy/policy.devcontainer.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "copilot-state" "/home/dev/.copilot"
	assert_named_volume_mount "$rendered_file" "agent" "copilot-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.devcontainer" "/project/.devcontainer"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.vscode" "/project/.vscode"
	assert_no_mount_target "$rendered_file" "agent" "/workspace/.idea"

	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "copilot"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "vscode"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.copilot.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.copilot.override.yml" ]
}

@test "cli init renders the effective codex compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-codex:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-codex:latest : echo 'ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012'"

	run init --batch --agent codex --mode cli --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/codex-cli.rendered.yml"
	render_cli_effective_compose "$PROJECT_DIR" "codex" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.codex.policy.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "codex-state" "/home/dev/.codex"
	assert_named_volume_mount "$rendered_file" "agent" "codex-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.idea" "/project/.idea"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.vscode" "/project/.vscode"

	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.codex.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.codex.override.yml" ]
}

@test "devcontainer init renders the effective codex compose stack" {
	export AGENTBOX_PROXY_IMAGE="ghcr.io/mattolson/agent-sandbox-proxy:latest"
	export AGENTBOX_AGENT_IMAGE="ghcr.io/mattolson/agent-sandbox-codex:latest"
	export AGENTBOX_ENABLE_SHELL_CUSTOMIZATIONS="true"
	export AGENTBOX_ENABLE_DOTFILES="true"
	export AGENTBOX_MOUNT_GIT_READONLY="true"
	export AGENTBOX_MOUNT_IDEA_READONLY="true"
	export AGENTBOX_MOUNT_VSCODE_READONLY="true"

	unset -f pull_and_pin_image
	stub pull_and_pin_image \
		"ghcr.io/mattolson/agent-sandbox-proxy:latest : echo 'ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123'" \
		"ghcr.io/mattolson/agent-sandbox-codex:latest : echo 'ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012'"

	run init --batch --agent codex --mode devcontainer --ide vscode --name project-sandbox --path "$PROJECT_DIR"
	assert_success

	local rendered_file="$BATS_TEST_TMPDIR/codex-devcontainer.rendered.yml"
	render_devcontainer_effective_compose "$PROJECT_DIR" "$rendered_file"

	assert_common_rendered_config \
		"$rendered_file" \
		"ghcr.io/mattolson/agent-sandbox-proxy@sha256:abc123" \
		"ghcr.io/mattolson/agent-sandbox-codex@sha256:jkl012"
	assert_common_optional_override_mounts "$rendered_file"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/user.agent.policy.yaml" "/project/.agent-sandbox/policy/user.agent.codex.policy.yaml"
	assert_bind_mount_suffix "$rendered_file" "proxy" "/etc/agent-sandbox/policy/devcontainer.policy.yaml" "/project/.agent-sandbox/policy/policy.devcontainer.yaml"
	assert_named_volume_mount "$rendered_file" "agent" "codex-state" "/home/dev/.codex"
	assert_named_volume_mount "$rendered_file" "agent" "codex-history" "/commandhistory"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.devcontainer" "/project/.devcontainer"
	assert_bind_mount_suffix "$rendered_file" "agent" "/workspace/.vscode" "/project/.vscode"
	assert_no_mount_target "$rendered_file" "agent" "/workspace/.idea"

	assert_devcontainer_json_file "$PROJECT_DIR/.devcontainer/devcontainer.json" "codex"
	assert_devcontainer_user_json_file "$PROJECT_DIR/.devcontainer/devcontainer.user.json"
	assert_devcontainer_managed_policy_file "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/policy.devcontainer.yaml" "vscode"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.policy.yaml"
	assert_shared_policy_scaffold "$PROJECT_DIR/$AGB_PROJECT_DIR/policy/user.agent.codex.policy.yaml"
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.override.yml" ]
	assert [ -f "$PROJECT_DIR/$AGB_PROJECT_DIR/compose/user.agent.codex.override.yml" ]
}
