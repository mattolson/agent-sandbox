#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"

write_policy_file() {
	local policy_file=$1
	shift
	local services
	services=$(printf '%s\n' "$@")

	require yq

	mkdir -p "$(dirname -- "$policy_file")"
	cp \
		"$AGB_TEMPLATEDIR/policy.yaml" \
		"$policy_file"

	services="$services" yq -i '.services = (strenv(services) | split("\n") )' "$policy_file"
}
