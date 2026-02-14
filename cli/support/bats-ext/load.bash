#!/bin/bash

# copy of standard bats `run` function
# runs the command with set -e
run() { # [!|-N] [--keep-empty-lines] [--separate-stderr] [--] <command to run...>
  # This has to be restored on exit from this function to avoid leaking our trap INT into surrounding code.
  # Non zero exits won't restore under the assumption that they will fail the test before it can be aborted,
  # which allows us to avoid duplicating the restore code on every exit path
  trap bats_interrupt_trap_in_run INT
  local expected_rc=
  local keep_empty_lines=
  local output_case=merged
  local has_flags=
  # parse options starting with -
  while [[ $# -gt 0 ]] && [[ $1 == -* || $1 == '!' ]]; do
    has_flags=1
    case "$1" in
    '!')
      expected_rc=-1
      ;;
    -[0-9]*)
      expected_rc=${1#-}
      if [[ $expected_rc =~ [^0-9] ]]; then
        printf "Usage error: run: '-NNN' requires numeric NNN (got: %s)\n" "$expected_rc" >&2
        return 1
      elif [[ $expected_rc -gt 255 ]]; then
        printf "Usage error: run: '-NNN': NNN must be <= 255 (got: %d)\n" "$expected_rc" >&2
        return 1
      fi
      ;;
    --keep-empty-lines)
      keep_empty_lines=1
      ;;
    --separate-stderr)
      output_case="separate"
      ;;
    --)
      shift # eat the -- before breaking away
      break
      ;;
    *)
      printf "Usage error: unknown flag '%s'" "$1" >&2
      return 1
      ;;
    esac
    shift
  done

  if [[ -n $has_flags ]]; then
    bats_warn_minimum_guaranteed_version "Using flags on \`run\`" 1.5.0
  fi

  # https://github.com/bats-core/bats-core/pull/1105
	unset output stderr lines stderr_lines

  local pre_command=

  case "$output_case" in
  merged) # redirects stderr into stdout and fills only $output/$lines
    pre_command=bats_merge_stdout_and_stderr
    ;;
  separate) # splits stderr into own file and fills $stderr/$stderr_lines too
    local bats_run_separate_stderr_file
    bats_run_separate_stderr_file="$(mktemp "${BATS_TEST_TMPDIR}/separate-stderr-XXXXXX")"
    pre_command=bats_redirect_stderr_into_file
    ;;
  esac

  local bats_run_stdout_file
  bats_run_stdout_file="$(mktemp "${BATS_TEST_TMPDIR}/run-stdout-XXXXXX")"

  local origFlags="$-"
  set +eET
  if [[ $keep_empty_lines ]]; then
    # 'output', 'status', 'lines' are global variables available to tests.
    # preserve trailing newlines by appending . and removing it later
    (
			set -e
			"$pre_command" "$@"
      status=$?
      printf .
      exit $status
		) >"$bats_run_stdout_file"
		status=$?
    output=$(cat "$bats_run_stdout_file")
    output="${output%.}"
  else
    # 'output', 'status', 'lines' are global variables available to tests.
		(
			set -e
			"$pre_command" "$@"
		) >"$bats_run_stdout_file"
		status=$?
    output=$(cat "$bats_run_stdout_file")
  fi

  bats_separate_lines lines output

  if [[ "$output_case" == separate ]]; then
    # shellcheck disable=SC2034
    read -d '' -r stderr <"$bats_run_separate_stderr_file" || true
    bats_separate_lines stderr_lines stderr
  fi

  # shellcheck disable=SC2034
  BATS_RUN_COMMAND="${*}"
  set "-$origFlags"

  bats_run_print_output() {
    if [[ -n "$output" ]]; then
      printf "%s\n" "$output"
    fi
    if [[ "$output_case" == separate && -n "$stderr" ]]; then
      printf "stderr:\n%s\n" "$stderr"
    fi
  }

  if [[ -n "$expected_rc" ]]; then
    if [[ "$expected_rc" = "-1" ]]; then
      if [[ "$status" -eq 0 ]]; then
      	# shellcheck disable=SC2034
        BATS_ERROR_SUFFIX=", expected nonzero exit code!"
        bats_run_print_output
        return 1
      fi
    elif [ "$status" -ne "$expected_rc" ]; then
      # shellcheck disable=SC2034
      BATS_ERROR_SUFFIX=", expected exit code $expected_rc, got $status"
      bats_run_print_output
      return 1
    fi
  elif [[ "$status" -eq 127 ]]; then # "command not found"
    bats_generate_warning 1 "$BATS_RUN_COMMAND"
  fi

  if [[ ${BATS_VERBOSE_RUN:-} ]]; then
    bats_run_print_output
  fi

  # don't leak our trap into surrounding code
  trap bats_interrupt_trap INT
}
