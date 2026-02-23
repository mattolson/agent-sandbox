#!/usr/bin/env bats

setup() {
	load test_helper

	# Create a mock run-compose script
	export AGB_LIBDIR="$BATS_TEST_TMPDIR/lib"
	mkdir -p "$AGB_LIBDIR"

	# shellcheck source=../../libexec/exec/exec
	source "$BATS_TEST_DIRNAME/../../libexec/exec/exec"
}

teardown() {
	unstub_all
}

@test "exec starts containers when agent is not running" {
	# run-compose ps returns empty (agent not running)
	cat > "$AGB_LIBDIR/run-compose" <<'SCRIPT'
#!/usr/bin/env bash
cmd="$1"; shift
case "$cmd" in
	ps)   [[ "$*" == "agent --status running --quiet" ]] || { echo "unexpected ps args: $*" >&2; exit 1; }; echo "" ;;
	up)   [[ "$*" == "-d" ]] || { echo "unexpected up args: $*" >&2; exit 1; }; echo "started" >&2 ;;
	exec) echo "run-compose exec $*" ;;
esac
SCRIPT
	chmod +x "$AGB_LIBDIR/run-compose"

	# Override exec to avoid replacing the test process
	exec() { "$@"; }

	run exec_function
	assert_success
	assert_output --partial "run-compose exec agent zsh"
}

@test "exec skips up when agent is already running" {
	cat > "$AGB_LIBDIR/run-compose" <<'SCRIPT'
#!/usr/bin/env bash
cmd="$1"; shift
case "$cmd" in
	ps)   [[ "$*" == "agent --status running --quiet" ]] || { echo "unexpected ps args: $*" >&2; exit 1; }; echo "abc123def456" ;;
	up)   echo "ERROR: up should not be called" >&2; exit 1 ;;
	exec) echo "run-compose exec $*" ;;
esac
SCRIPT
	chmod +x "$AGB_LIBDIR/run-compose"

	exec() { "$@"; }

	run exec_function
	assert_success
	assert_output --partial "run-compose exec agent zsh"
	refute_output --partial "ERROR: up should not be called"
}

@test "exec passes custom shell argument" {
	cat > "$AGB_LIBDIR/run-compose" <<'SCRIPT'
#!/usr/bin/env bash
cmd="$1"; shift
case "$cmd" in
	ps)   [[ "$*" == "agent --status running --quiet" ]] || { echo "unexpected ps args: $*" >&2; exit 1; }; echo "abc123def456" ;;
	exec) echo "run-compose exec $*" ;;
esac
SCRIPT
	chmod +x "$AGB_LIBDIR/run-compose"

	exec() { "$@"; }

	run exec_function bash
	assert_success
	assert_output --partial "run-compose exec agent bash"
}
