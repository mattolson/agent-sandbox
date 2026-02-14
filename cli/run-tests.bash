#!/bin/bash
set -euo pipefail

# workaround for https://github.com/bats-core/bats-core/issues/1086

export LC_ALL=C

coverage=false
if [[ ${1-} == "--coverage" ]]
then
	coverage=true
	shift
fi

# shellcheck disable=SC2206
test_dirs=(${@-test/*/})

: "${bats_cmd:=support/bats/bin/bats}"

if "$coverage"
then
	if command -v kcov &>/dev/null
	then
		kcov_cmd=$(command -v kcov)
	elif command -v support/usr/local/bin/kcov &>/dev/null
	then
		kcov_cmd=$(command -v support/usr/local/bin/kcov)
	else
		>&2 echo "$0: kcov required"
		exit 1
	fi

	coverage_dir='.coverage'
	rm -rf "$coverage_dir"
	mkdir -p "$coverage_dir/partial" "$coverage_dir/merged"
fi

echo "Found ${#test_dirs[@]} test suites."

success=true
for dir in "${test_dirs[@]}"
do
	name=$(basename "$dir")
	echo "--- $name ---"
	if "$coverage"
	then
		# Hide stderr: https://github.com/SimonKagstrom/kcov/issues/464
		"$kcov_cmd" \
			--include-path=bin,lib,libexec \
			"$coverage_dir/partial/$name" \
			"$bats_cmd" \
			--filter-tags '!no-coverage' \
			${BATS_OPTS:-} \
			${bats_opts:-} \
			"$dir" 2>/dev/null ||
			success=false
	else
		"$bats_cmd" \
			${BATS_OPTS:-} \
			${bats_opts:-} \
			"$dir" ||
			success=false
	fi
done

if "$coverage"
then
	echo "Merging coverage reports..."
	# shellcheck disable=SC2086
	"$kcov_cmd" --merge "$coverage_dir/merged" "$coverage_dir"/partial/*
	echo "Coverage report generated at file://$PWD/$coverage_dir/merged/index.html"

	echo "Total $(jq -r '.percent_covered' <"$coverage_dir/merged/kcov-merged/coverage.json")%"
fi

if "$success"
then
	tput setaf 2
	tput bold
	echo "✓ All tests passed in ${SECONDS} seconds."
else
	tput setaf 1
	tput bold
	echo "✗ Some tests failed in ${SECONDS} seconds."
	exit 1
fi

tput sgr0
