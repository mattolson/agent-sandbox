#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../bats-mock/stub.bash"

export BATS_MOCK_REAL_basename=$(which basename)
export BATS_MOCK_REAL_echo=$(which echo)

unstub_all() {
	local program result=0
	if [ -d "${BATS_MOCK_BINDIR}" ]; then
	  for program in $(shopt -s nullglob; echo "${BATS_MOCK_BINDIR}"/*); do
	    program=$("${BATS_MOCK_REAL_basename}" "${program}")
	    if ! unstub "${program}"
	    then
	      "$BATS_MOCK_REAL_echo" "${program} has failed expectations"
	      result=1
	    fi
	  done
	fi
	return $result
}
