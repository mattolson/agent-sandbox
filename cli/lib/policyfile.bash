#!/usr/bin/env bash

# shellcheck source=require.bash
source "$AGB_LIBDIR/require.bash"

copy_policy_template() {
	local policy_file=$1
	local template_name=$2

	mkdir -p "$(dirname -- "$policy_file")"
	cp "$AGB_TEMPLATEDIR/$template_name" "$policy_file"
}

write_policy_file() {
	local policy_file=$1
	shift
	local services
	services=$(printf '%s\n' "$@")

	require yq

	copy_policy_template "$policy_file" "policy.yaml"

	services="$services" yq -i '.services = (strenv(services) | split("\n") )' "$policy_file"
}

scaffold_user_policy_file_if_missing() {
	local policy_file=$1
	local template_name=$2

	if [[ -f "$policy_file" ]]
	then
		return 0
	fi

	copy_policy_template "$policy_file" "$template_name"
}
