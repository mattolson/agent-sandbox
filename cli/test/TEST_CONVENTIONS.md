# BATS Test Conventions

## Structure

```
cli/test/<module>/
├── test_helper.bash       # Standard setup (see below)
└── <function>.bats        # One file per function
```

## test_helper.bash Template

```bash
#!/bin/bash
bats_require_minimum_version 1.5.0
# Enable Bash 3.2 compat mode when running on Bash 4.4+
# On actual Bash 3.2 (macOS default), these options don't exist and aren't needed.
if shopt -s compat32 2>/dev/null; then
	export BASH_COMPAT=3.2
fi
set -uo pipefail
export SHELLOPTS

AGB_ROOT="$BATS_TEST_DIRNAME/../.."
BATS_LIB_PATH="$AGB_ROOT/support":${BATS_LIB_PATH-}

bats_load_library bats-ext
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-mock-ext

export AGB_ROOT AGB_LIBDIR="$AGB_ROOT/lib"
```

## Test File Template

```bash
#!/usr/bin/env bats

setup() {
	load test_helper
	source "$AGB_LIBDIR/<module>.bash"
	TEST_FILE="$BATS_TEST_TMPDIR/file.yml"
	touch "$TEST_FILE"  # Create files in setup if used by multiple tests
}

teardown() {
	unstub_all
}

@test "descriptive name" {
	run function_name "args"
	assert_success
	assert_output "expected"
}
```

Don't add comments that restate what a command does.
Use `touch` to create empty files if contents don't matter for the test.

## Assertions

- `assert_success` / `assert_failure` - Exit code
- `assert_output "exact"` - Exact match
- `assert_output --partial "substr"` - Contains
- `assert_line "text"` - Specific line
- `assert_equal "$actual" "$expected"` - Equality

Use `run` only when you need to check exit code or output. Never capture output with `$()`.
If the only assertion would be `assert_success`, run the command directly without `run`/`assert_success`.
Never use `2>&1` with `run` - it already captures both stdout and stderr.

## Stubbing

```bash
stub docker \
	"pull image:tag : :" \
	"inspect image:tag : echo 'output'"
```

- Match exact args
- `: :` = silent success (default, use unless output needed)
- `: echo 'output'` = return specific output only when needed
- `unstub_all` in teardown (never manual `unstub`)

## yq Usage

### Existence Checks

Use `yq -e` (exits non-zero if no match):

```bash
yq -e '.services.agent.volumes[] | select(. == "exact:match")' "$FILE"
```

Without `-e`, no match still exits 0 (false positive).

### Variable Interpolation

Use `env()`, not string concatenation:

```bash
var="$var" run yq -e '.volumes | select(has(env(var)))' "$FILE"
```

## Testability Pattern

Extract pure functions from user interaction:

```bash
# Pure (test without stubs)
set_image() { yq -i '.services.agent.image = env(image)' "$file"; }

# Orchestrator (one integration test with stubs)
customize_file() {
	image=$(read_line "Image:")
	set_image "$image"
}
```

Unit tests: test what function does, not what it preserves.
Integration tests: verify all outputs, stub all input.
