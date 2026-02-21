#!/usr/bin/env bash
# Select wrappers, can be replaced with more advanced alternatives, e.g. whiplash

# Prompts the user for a yes/no answer.
# Args:
#   $1 - The prompt text to display
# Outputs:
#   "true" if the user answered "yes", "false" otherwise
select_yes_no() {
	local prompt="$1"
	local answer

	read -rp "$prompt [y/N]: " answer >&2
	if [[ $answer =~ ^[Yy]$ ]]
	then
		echo "true"
	else
		echo "false"
	fi
}

# Prompts the user to select one option from a list.
# Args:
#   $1 - The prompt text to display
#   $@ - The options to present (remaining arguments)
# Outputs:
#   The selected option to stdout
select_option() {
	local prompt="$1"
	shift
	local options=("$@")
	local default="${options[0]}"
	local i

	for i in "${!options[@]}"; do
		echo "  $((i+1))) ${options[$i]}" >&2
	done

	local reply
	while true; do
		read -rp "$prompt [$default] " reply >&2
		if [[ -z $reply ]]; then
			printf '%s\n' "$default"
			return
		fi
		if [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#options[@]} )); then
			printf '%s\n' "${options[$((reply-1))]}"
			return
		fi
		echo "Invalid selection, try again." >&2
	done
}

# Prompts the user to enter a single line of text.
# Args:
#   $1 - The prompt text to display
# Outputs:
#   The entered text to stdout
read_line() {
	local prompt="$1"
	local input

	read -rp "$prompt " input >&2
	printf '%s\n' "$input"
}

# Opens a file in the user's preferred editor.
# Args:
#   $1 - The file path to open
# Environment:
#   EDITOR - Preferred editor command (fallback: open, vi)
#   VISUAL - Visual editor command (takes precedence over EDITOR)
open_editor() {
	local file="$1"

	local editor="${VISUAL:-${EDITOR:-$(command -v open || echo vi)}}"

	if ! command -v "${editor%% *}" &>/dev/null
	then
		echo "$0: editor '$editor' not found. Set EDITOR or VISUAL environment variable." >&2
		return 1
	fi

	local -a editor_cmd
	read -ra editor_cmd <<<"$editor"

	if [[ ${editor_cmd[0]} == */open ]]
	then
		"${editor_cmd[@]}" --new --wait-apps "$file" </dev/tty >/dev/tty
	else
		"${editor_cmd[@]}" "$file" </dev/tty >/dev/tty
	fi

}
