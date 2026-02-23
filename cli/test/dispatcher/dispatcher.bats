#!/usr/bin/env bats

AGENTBOX="$BATS_TEST_DIRNAME/../../bin/agentbox"

setup() {
	load test_helper

	# Create a mock libexec tree for isolation
	export MOCK_ROOT="$BATS_TEST_TMPDIR/cli"
	export MOCK_LIBEXECDIR="$MOCK_ROOT/libexec"
	export MOCK_LIBDIR="$MOCK_ROOT/lib"

	mkdir -p "$MOCK_LIBEXECDIR/alpha"
	mkdir -p "$MOCK_LIBEXECDIR/beta"
	mkdir -p "$MOCK_LIBDIR"

	# Create mock executables
	cat > "$MOCK_LIBEXECDIR/alpha/start" <<'SCRIPT'
#!/usr/bin/env bash
echo "alpha-start called with: $*"
SCRIPT
	chmod +x "$MOCK_LIBEXECDIR/alpha/start"

	cat > "$MOCK_LIBEXECDIR/alpha/alpha" <<'SCRIPT'
#!/usr/bin/env bash
if [[ $# -gt 0 ]]; then
	echo "alpha default called with: $*"
else
	echo "alpha default called"
fi
SCRIPT
	chmod +x "$MOCK_LIBEXECDIR/alpha/alpha"

	# Version mock (called before most dispatches)
	mkdir -p "$MOCK_LIBEXECDIR/version"
	cat > "$MOCK_LIBEXECDIR/version/version" <<'SCRIPT'
#!/usr/bin/env bash
:
SCRIPT
	chmod +x "$MOCK_LIBEXECDIR/version/version"

	# run-compose mock
	cat > "$MOCK_LIBDIR/run-compose" <<'SCRIPT'
#!/usr/bin/env bash
echo "run-compose $*"
SCRIPT
	chmod +x "$MOCK_LIBDIR/run-compose"

	# Copy compat.bash so the dispatcher can source it
	cp "$AGB_LIBDIR/compat.bash" "$MOCK_LIBDIR/compat.bash"

	# Create a wrapper that redirects AGB_ROOT to our mock tree
	WRAPPER="$BATS_TEST_TMPDIR/agentbox-wrapper"
	cat > "$WRAPPER" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
export AGB_ROOT="$MOCK_ROOT"
export AGB_LIBDIR="$MOCK_LIBDIR"
export AGB_LIBEXECDIR="$MOCK_LIBEXECDIR"
export AGB_TEMPLATEDIR="$MOCK_ROOT/templates"
source "\$AGB_LIBDIR/compat.bash"

local_modules=()
mapfile -t local_modules < <(
	find "\$AGB_LIBEXECDIR" -mindepth 1 -maxdepth 1 -type d -print |
	while IFS= read -r; do basename -- "\$REPLY"; done | sort
)

if [[ \$# -lt 1 ]]; then
	echo "Usage: agentbox <\$(IFS='|'; echo "\${local_modules[*]}")> [command] [args...]" >&2
	exit 1
fi

module="\$1"; shift

# Check if module is a known module
if ! printf '%s\n' "\${local_modules[@]}" | grep -qx "\$module"; then
	"\$AGB_LIBEXECDIR/version/version" "Agent Sandbox"
	exec "\$AGB_LIBDIR/run-compose" "\$module" "\$@"
fi

command="\${1:-}"
if [[ -z "\$command" || "\${command:0:1}" == "-" ]]; then
	command="\$module"
else
	shift
fi

if [[ "\$command" == "help" ]]; then
	echo "Commands in \$module:" >&2
	for f in "\$AGB_LIBEXECDIR/\$module"/*; do
		[[ -f "\$f" && -x "\$f" ]] && { echo -n '  '; basename -- "\$f"; }
	done | sort >&2
	exit 0
fi

exec_path="\$AGB_LIBEXECDIR/\$module/\$command"
if [[ -x "\$exec_path" ]]; then
	if [[ "\$module" != "version" ]]; then
		"\$AGB_LIBEXECDIR/version/version" "Agent Sandbox"
	fi
	exec "\$exec_path" "\$@"
fi

# Fallback
exec_path="\$AGB_LIBEXECDIR/\$module/_"
if [[ -x "\$exec_path" ]]; then
	exec "\$exec_path" "\$command" "\$@"
fi

echo "Command '\$command' not found in \$module" >&2
exit 127
SCRIPT
	chmod +x "$WRAPPER"
}

teardown() {
	unstub_all
}

@test "no arguments exits 1 with usage" {
	run "$AGENTBOX"
	assert_failure
	assert_output --partial "Usage:"
}

@test "known module with command routes to correct executable" {
	run "$WRAPPER" alpha start --flag
	assert_success
	assert_output "alpha-start called with: --flag"
}

@test "module without command uses module name as command" {
	run "$WRAPPER" alpha
	assert_success
	assert_output "alpha default called"
}

@test "command not found in module exits 127" {
	run -127 "$WRAPPER" alpha nonexistent
	assert_output --partial "not found"
}

@test "unknown command falls through to docker compose" {
	run "$WRAPPER" ps
	assert_success
	assert_output "run-compose ps"
}

@test "module help lists commands" {
	run "$WRAPPER" alpha help
	assert_success
	assert_output --partial "Commands in alpha:"
	assert_output --partial "start"
}
