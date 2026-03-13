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

remove_service_from_policy_file() {
	require yq
	local policy_file=$1
	local service=$2

	service="$service" yq -i \
		'.services = ((.services // []) | map(select(. != env(service))))' "$policy_file"
}

deprecated_policy_file_path() {
	local policy_file=$1
	local directory
	local basename
	local stem
	local extension
	local candidate
	local suffix=2

	directory="$(dirname -- "$policy_file")"
	basename="$(basename -- "$policy_file")"
	stem="${basename%.yaml}"
	extension=""

	if [[ "$basename" == *.yaml ]]
	then
		extension=".yaml"
	fi

	candidate="$directory/${stem}.deprecated${extension}"
	while [[ -e "$candidate" ]]
	do
		candidate="$directory/${stem}.deprecated.$suffix${extension}"
		suffix=$((suffix + 1))
	done

	printf '%s\n' "$candidate"
}

rename_policy_file_as_deprecated() {
	local policy_file=$1
	local shared_policy_file=$2
	local agent_policy_file=$3
	local deprecated_file
	local tmp_file

	if [[ ! -f "$policy_file" ]]
	then
		return 1
	fi

	deprecated_file="$(deprecated_policy_file_path "$policy_file")"
	mv "$policy_file" "$deprecated_file"
	tmp_file="${deprecated_file}.tmp"

	{
		printf '%s\n' \
			"# Deprecated by agentbox. This file is no longer read." \
			"# Use $shared_policy_file and $agent_policy_file instead." \
			"# Preserved for reference during the layered policy migration." \
			""
		cat "$deprecated_file"
	} > "$tmp_file"
	mv "$tmp_file" "$deprecated_file"

	printf '%s\n' "$deprecated_file"
}

carry_forward_legacy_cli_policy_file() {
	local legacy_policy_file=$1
	local agent_policy_file=$2
	local agent=$3
	local shared_policy_file=$4

	if [[ ! -f "$legacy_policy_file" ]]
	then
		return 1
	fi

	if [[ ! -f "$agent_policy_file" ]]
	then
		mkdir -p "$(dirname -- "$agent_policy_file")"
		cp "$legacy_policy_file" "$agent_policy_file"
		remove_service_from_policy_file "$agent_policy_file" "$agent"
	fi

	rename_policy_file_as_deprecated "$legacy_policy_file" "$shared_policy_file" "$agent_policy_file" >/dev/null
}
