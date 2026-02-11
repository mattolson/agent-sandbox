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
	local PS3="$prompt "

	local choice
	select choice in "${options[@]}"; do
		if [[ -n $choice ]]
		then
			printf '%s\n' "$choice"
			break
		else
			echo "Invalid selection, try again." >&2
		fi
	done
}

# Prompts the user to select multiple options from a list.
# Args:
#   $1 - The prompt text to display
#   $@ - The options to present (remaining arguments)
# Outputs:
#   Each selected option on a separate line to stdout
select_multiple() {
	printf '%s\n' "$1" >&2
	shift

	for opt in "$@"
	do
		read -rp "Select $opt? [y/N]: " answer >&2
		if [[ $answer =~ ^[Yy]$ ]]
		then
			printf '%s\n' "$opt"
		fi
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

# Prompts the user to enter multiple lines of text until an empty line is entered.
# Args:
#   $1 - The prompt text to display
# Outputs:
#   Each entered line to stdout (empty line terminates input)
read_multiline() {
	printf '%s\n' "$1" >&2
	shift

	local line
	while true
	do
		read -r -p "> " line >&2 || break
		[[ -z $line ]] && break
		printf '%s\n' "$line"
	done
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

	if [[ $editor == */open ]]; then
		$editor --new --wait-apps "$file" </dev/tty >/dev/tty
	else
		$editor "$file" </dev/tty >/dev/tty
	fi
}
