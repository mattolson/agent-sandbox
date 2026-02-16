#!/bin/bash
bats_require_minimum_version 1.5.0

shopt -s compat32
export BASH_COMPAT=3.2
set -uo pipefail
export SHELLOPTS

AGB_ROOT="$BATS_TEST_DIRNAME/../.."
BATS_LIB_PATH="$AGB_ROOT/support":${BATS_LIB_PATH-}

bats_load_library bats-ext
bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-mock-ext

export AGB_ROOT AGB_LIBDIR="$AGB_ROOT/lib"

export AGB_PROJECT_DIR='./.agent-sandbox'
