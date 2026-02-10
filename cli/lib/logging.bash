#!/usr/bin/env bash

# Logging helpers
# Example usage:
# `echo 'Terrible error' | error`

if ! command -v tput &>/dev/null
then
	tput() { :; }
fi

debug() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	tput setaf 6
	tput bold
	echo -n '[DEBUG] '
	tput sgr0
	cat -
}

info() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	tput setaf 4
	tput bold
	echo -n '[INFO] '
	tput sgr0
	cat -
}

warning() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	tput setaf 3
	tput bold
	echo -n '[WARN] '
	tput sgr0
	cat -
}

error() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	tput setaf 1
	tput bold
	echo -n '[ERROR] '
	tput sgr0
	cat -
}
