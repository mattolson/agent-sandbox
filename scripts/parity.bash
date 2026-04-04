#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PARITY_ROOT="$ROOT_DIR/testdata/parity"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

require_command() {
	if ! command -v "$1" >/dev/null 2>&1
	then
		echo "scripts/parity.bash: required command not found: $1" >&2
		exit 1
	fi
}

build_go_cli() {
	if [[ -n "${AGENTBOX_GO_BIN:-}" ]]
	then
		GO_CLI_BIN="$AGENTBOX_GO_BIN"
		return
	fi

	GO_CLI_BIN="$TMP_ROOT/agentbox-go"
	(
		cd "$ROOT_DIR"
		go build -o "$GO_CLI_BIN" ./cmd/agentbox
	)
}

write_fake_docker() {
	local path=$1
	cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

lookup_value() {
	local key=$1
	local value
	while IFS='=' read -r map_key value
	do
		[[ -n "$map_key" ]] || continue
		if [[ "$map_key" == "$key" ]]
		then
			printf '%s\n' "$value"
			return 0
		fi
	done <<<"${AGENTBOX_PARITY_IMAGE_DIGESTS:-}"

	return 1
}

printf '%s\n' "$*" >> "${AGENTBOX_PARITY_DOCKER_LOG:?}"

	case "$1" in
	pull)
		exit 0
		;;
	inspect)
		lookup_value "${*: -1}"
		exit 0
		;;
	image)
		if [[ "${2:-}" == "inspect" ]]
		then
			lookup_value "${*: -1}" >/dev/null
			echo "[]"
			exit 0
		fi
		;;
	compose)
		if [[ "$*" == *" ps "* ]] && [[ "$*" == *"--status running --quiet"* ]]
		then
			if [[ "${AGENTBOX_PARITY_RUNNING:-false}" == "true" ]]
			then
				echo "running"
			fi
			exit 0
		fi
		exit 0
		;;
esac

echo "unsupported fake docker invocation: $*" >&2
exit 1
EOF
	chmod +x "$path"
}

write_fake_editor() {
	local path=$1
	cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

file=$1
printf '%s\n' "$file" >> "${AGENTBOX_PARITY_EDITOR_LOG:?}"

if [[ -n "${AGENTBOX_PARITY_EDITOR_DELAY_SECONDS:-}" ]]
then
	sleep "$AGENTBOX_PARITY_EDITOR_DELAY_SECONDS"
fi

if [[ -n "${AGENTBOX_PARITY_EDITOR_APPEND:-}" ]]
then
	printf '%s' "$AGENTBOX_PARITY_EDITOR_APPEND" >> "$file"
fi
EOF
	chmod +x "$path"
}

normalize_console_file() {
	local repo_root=$1
	local file=$2
	local text
	text=$(tr -d '\r' <"$file" | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2} \[[A-Z]+\] //')
	printf '%s' "${text//$repo_root/\$REPO}"
}

normalize_stderr_file() {
	normalize_console_file "$@"
}

normalize_text_file() {
	local repo_root=$1
	local file=$2
	local text=""
	if [[ -f "$file" ]]
	then
		text=$(<"$file")
	fi
	printf '%s' "${text//$repo_root/\$REPO}"
}

run_with_pty() {
	local stdout_file=$1
	local stderr_file=$2
	shift 2

	if script --version >/dev/null 2>&1
	then
		local quoted_command=""
		printf -v quoted_command '%q ' "$@"
		script -qec "$quoted_command" /dev/null >"$stdout_file" 2>"$stderr_file"
		return
	fi

	script -q /dev/null "$@" >"$stdout_file" 2>"$stderr_file"
}

run_cli_case() {
	local label=$1
	local cli_bin=$2
	local case_name=$3
	shift 3
	local case_root="$TMP_ROOT/$case_name/$label"
	local repo_root="$case_root/repo"
	local bin_dir="$case_root/bin"
	local fixture_root="$PARITY_ROOT/$case_name/repo"
	local stdout_file="$case_root/stdout"
	local stderr_file="$case_root/stderr"
	local status_file="$case_root/status"
	local docker_log="$case_root/docker.log"
	local editor_log="$case_root/editor.log"
	local command_name="${1:-}"

	mkdir -p "$repo_root" "$bin_dir"
	cp -R "$fixture_root/." "$repo_root"
	: >"$docker_log"
	: >"$editor_log"
	write_fake_docker "$bin_dir/docker"
	write_fake_editor "$bin_dir/editor"

	local status=0
	if [[ "$label" == "bash" && "$command_name" == "edit" ]]
	then
		(
			cd "$repo_root"
			PATH="$bin_dir:$PATH" \
			VISUAL="$bin_dir/editor" \
			EDITOR="$bin_dir/editor" \
			AGENTBOX_PARITY_DOCKER_LOG="$docker_log" \
			AGENTBOX_PARITY_EDITOR_LOG="$editor_log" \
			AGENTBOX_PARITY_RUNNING="${AGENTBOX_PARITY_RUNNING:-false}" \
			AGENTBOX_PARITY_IMAGE_DIGESTS="${AGENTBOX_PARITY_IMAGE_DIGESTS:-}" \
			AGENTBOX_PARITY_EDITOR_DELAY_SECONDS="${AGENTBOX_PARITY_EDITOR_DELAY_SECONDS:-}" \
			AGENTBOX_PARITY_EDITOR_APPEND="${AGENTBOX_PARITY_EDITOR_APPEND:-}" \
			run_with_pty "$stdout_file" "$stderr_file" "$cli_bin" "$@"
		) || status=$?
	else
		(
			cd "$repo_root"
			PATH="$bin_dir:$PATH" \
			VISUAL="$bin_dir/editor" \
			EDITOR="$bin_dir/editor" \
			AGENTBOX_PARITY_DOCKER_LOG="$docker_log" \
			AGENTBOX_PARITY_EDITOR_LOG="$editor_log" \
			AGENTBOX_PARITY_RUNNING="${AGENTBOX_PARITY_RUNNING:-false}" \
			AGENTBOX_PARITY_IMAGE_DIGESTS="${AGENTBOX_PARITY_IMAGE_DIGESTS:-}" \
			AGENTBOX_PARITY_EDITOR_DELAY_SECONDS="${AGENTBOX_PARITY_EDITOR_DELAY_SECONDS:-}" \
			AGENTBOX_PARITY_EDITOR_APPEND="${AGENTBOX_PARITY_EDITOR_APPEND:-}" \
			"$cli_bin" "$@" >"$stdout_file" 2>"$stderr_file"
		) || status=$?
	fi
	printf '%s\n' "$status" >"$status_file"
}

assert_equal() {
	local got=$1
	local want=$2
	local message=$3
	if [[ "$got" != "$want" ]]
	then
		echo "parity failure: $message" >&2
		echo "got:" >&2
		printf '%s\n' "$got" >&2
		echo "want:" >&2
		printf '%s\n' "$want" >&2
		exit 1
	fi
}

assert_contains() {
	local haystack=$1
	local needle=$2
	local message=$3
	if [[ "$haystack" != *"$needle"* ]]
	then
		echo "parity failure: $message" >&2
		echo "missing: $needle" >&2
		echo "in:" >&2
		printf '%s\n' "$haystack" >&2
		exit 1
	fi
}

status_of() {
	cat "$TMP_ROOT/$1/$2/status"
}

repo_of() {
	printf '%s\n' "$TMP_ROOT/$1/$2/repo"
}

docker_log_of() {
	printf '%s\n' "$TMP_ROOT/$1/$2/docker.log"
}

editor_log_of() {
	printf '%s\n' "$TMP_ROOT/$1/$2/editor.log"
}

stderr_of() {
	printf '%s\n' "$TMP_ROOT/$1/$2/stderr"
}

stdout_of() {
	printf '%s\n' "$TMP_ROOT/$1/$2/stdout"
}

run_bump_layered() {
	AGENTBOX_PARITY_RUNNING=false
	AGENTBOX_PARITY_IMAGE_DIGESTS=$'ghcr.io/example/proxy:latest=ghcr.io/example/proxy@sha256:abc123\nghcr.io/example/claude:latest=ghcr.io/example/claude@sha256:def456'
	AGENTBOX_PARITY_EDITOR_APPEND=
	AGENTBOX_PARITY_EDITOR_DELAY_SECONDS=
	run_cli_case bash "$ROOT_DIR/cli/bin/agentbox" bump-layered bump
	run_cli_case go "$GO_CLI_BIN" bump-layered bump

	assert_equal "$(status_of bump-layered bash)" "0" "bash bump-layered exit status"
	assert_equal "$(status_of bump-layered go)" "0" "go bump-layered exit status"

	for label in bash go
	do
		local repo_root
		repo_root=$(repo_of bump-layered "$label")
		assert_equal "$(yq -r '.services.proxy.image' "$repo_root/.agent-sandbox/compose/base.yml")" "ghcr.io/example/proxy@sha256:abc123" "$label bump proxy digest"
		assert_equal "$(yq -r '.services.agent.image' "$repo_root/.agent-sandbox/compose/agent.claude.yml")" "ghcr.io/example/claude@sha256:def456" "$label bump agent digest"
		assert_equal "$(<"$repo_root/.agent-sandbox/compose/user.override.yml")" "$(<"$PARITY_ROOT/bump-layered/repo/.agent-sandbox/compose/user.override.yml")" "$label shared override preserved"
		normalized_stderr=$(normalize_stderr_file "$repo_root" "$(stderr_of bump-layered "$label")")
		assert_contains "$normalized_stderr" "Found layered compose files (mode: cli)" "$label bump mode banner"
		assert_contains "$normalized_stderr" "Bump complete" "$label bump completion banner"
	done

	assert_equal "$(normalize_text_file "$(repo_of bump-layered bash)" "$(docker_log_of bump-layered bash)")" "$(normalize_text_file "$(repo_of bump-layered go)" "$(docker_log_of bump-layered go)")" "bump-layered docker calls"
}

run_bump_legacy_layout() {
	AGENTBOX_PARITY_RUNNING=false
	AGENTBOX_PARITY_IMAGE_DIGESTS=
	AGENTBOX_PARITY_EDITOR_APPEND=
	AGENTBOX_PARITY_EDITOR_DELAY_SECONDS=
	run_cli_case bash "$ROOT_DIR/cli/bin/agentbox" bump-legacy-layout bump
	run_cli_case go "$GO_CLI_BIN" bump-legacy-layout bump

	if [[ "$(status_of bump-legacy-layout bash)" == "0" || "$(status_of bump-legacy-layout go)" == "0" ]]
	then
		echo "parity failure: expected bump-legacy-layout to fail for both CLIs" >&2
		exit 1
	fi

	for label in bash go
	do
		local repo_root normalized_stderr
		repo_root=$(repo_of bump-legacy-layout "$label")
		normalized_stderr=$(normalize_stderr_file "$repo_root" "$(stderr_of bump-legacy-layout "$label")")
		assert_contains "$normalized_stderr" "does not support the legacy single-file layout" "$label legacy-layout banner"
		assert_contains "$normalized_stderr" ".agent-sandbox/docker-compose.legacy.yml" "$label legacy rename guidance"
		assert_contains "$normalized_stderr" "docs/upgrades/m8-layered-layout.md" "$label legacy upgrade guide"
	done
}

run_switch_running() {
	AGENTBOX_PARITY_RUNNING=true
	AGENTBOX_PARITY_IMAGE_DIGESTS=
	AGENTBOX_PARITY_EDITOR_APPEND=
	AGENTBOX_PARITY_EDITOR_DELAY_SECONDS=
	run_cli_case bash "$ROOT_DIR/cli/bin/agentbox" switch-running switch --agent codex
	run_cli_case go "$GO_CLI_BIN" switch-running switch --agent codex

	assert_equal "$(status_of switch-running bash)" "0" "bash switch-running exit status"
	assert_equal "$(status_of switch-running go)" "0" "go switch-running exit status"

	for label in bash go
	do
		local repo_root normalized_stderr
		repo_root=$(repo_of switch-running "$label")
		assert_contains "$(<"$repo_root/.agent-sandbox/active-target.env")" "ACTIVE_AGENT=codex" "$label switch wrote target state"
		normalized_stderr=$(normalize_stderr_file "$repo_root" "$(stderr_of switch-running "$label")")
		assert_contains "$normalized_stderr" "Restarting containers to apply the switch" "$label switch restart banner"
	done

	assert_equal "$(normalize_text_file "$(repo_of switch-running bash)" "$(docker_log_of switch-running bash)")" "$(normalize_text_file "$(repo_of switch-running go)" "$(docker_log_of switch-running go)")" "switch-running docker calls"
}

run_edit_policy_inactive_agent() {
	AGENTBOX_PARITY_RUNNING=false
	AGENTBOX_PARITY_IMAGE_DIGESTS=
	AGENTBOX_PARITY_EDITOR_APPEND=$'\n# parity edit\n'
	AGENTBOX_PARITY_EDITOR_DELAY_SECONDS=1
	run_cli_case bash "$ROOT_DIR/cli/bin/agentbox" edit-policy-inactive-agent edit policy --agent codex
	run_cli_case go "$GO_CLI_BIN" edit-policy-inactive-agent edit policy --agent codex

	assert_equal "$(status_of edit-policy-inactive-agent bash)" "0" "bash edit-policy exit status"
	assert_equal "$(status_of edit-policy-inactive-agent go)" "0" "go edit-policy exit status"

	for label in bash go
	do
		local repo_root normalized_stderr normalized_editor_log
		repo_root=$(repo_of edit-policy-inactive-agent "$label")
		normalized_stderr="$(normalize_console_file "$repo_root" "$(stdout_of edit-policy-inactive-agent "$label")")$(normalize_stderr_file "$repo_root" "$(stderr_of edit-policy-inactive-agent "$label")")"
		normalized_editor_log=$(normalize_text_file "$repo_root" "$(editor_log_of edit-policy-inactive-agent "$label")")
		assert_contains "$normalized_stderr" "inactive agent 'codex'" "$label inactive-agent warning"
		assert_equal "$normalized_editor_log" '$REPO/.agent-sandbox/policy/user.agent.codex.policy.yaml' "$label edit target"
		assert_equal "$(normalize_text_file "$repo_root" "$(docker_log_of edit-policy-inactive-agent "$label")")" "" "$label inactive-agent should not call docker"
		assert_contains "$(<"$repo_root/.agent-sandbox/policy/user.agent.codex.policy.yaml")" "# parity edit" "$label policy edit persisted"
	done
}

main() {
	require_command go
	require_command yq
	build_go_cli

	local -a cases=(bump-layered bump-legacy-layout switch-running edit-policy-inactive-agent)
	if [[ $# -gt 0 ]]
	then
		cases=("$@")
	fi

	for case_name in "${cases[@]}"
	do
		case "$case_name" in
		bump-layered)
			run_bump_layered
			;;
		bump-legacy-layout)
			run_bump_legacy_layout
			;;
		switch-running)
			run_switch_running
			;;
		edit-policy-inactive-agent)
			run_edit_policy_inactive_agent
			;;
		*)
			echo "scripts/parity.bash: unknown case '$case_name'" >&2
			exit 1
			;;
		esac
		echo "PASS $case_name"
	done
}

main "$@"
