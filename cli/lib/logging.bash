#!/usr/bin/env bash

# Logging helpers
# Example usage:
# `echo 'Terrible error' | error`

if ! command -v tput &>/dev/null
then
	tput() { :; }
fi

safe_tput() {
	tput "$@" 2>/dev/null || true
}

debug() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	safe_tput setaf 6
	safe_tput bold
	echo -n '[DEBUG] '
	safe_tput sgr0
	cat -
} >&2

info() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	safe_tput setaf 4
	safe_tput bold
	echo -n '[INFO] '
	safe_tput sgr0
	cat -
} >&2

warning() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	safe_tput setaf 3
	safe_tput bold
	echo -n '[WARN] '
	safe_tput sgr0
	cat -
} >&2

error() {
	# shellcheck disable=SC2312
	date +%T | tr '\n' ' '
	safe_tput setaf 1
	safe_tput bold
	echo -n '[ERROR] '
	safe_tput sgr0
	cat -
} >&2
