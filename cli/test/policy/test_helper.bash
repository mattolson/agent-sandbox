#!/bin/bash

bats_require_minimum_version 1.5.0

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
export AGB_TEMPLATEDIR="$AGB_ROOT/templates"
export AGB_PROJECT_DIR='.agent-sandbox'
