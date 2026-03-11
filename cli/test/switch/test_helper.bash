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

export AGB_ROOT
export AGB_LIBDIR="$AGB_ROOT/lib"
export AGB_LIBEXECDIR="$AGB_ROOT/libexec"
