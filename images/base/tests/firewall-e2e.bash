#!/usr/bin/env bash
# End-to-end test of the agent firewall and the proxy's DNS sinkhole and address guard.
#
# Starts the proxy and an agent running the bare base image on one compose network, with IPv6 on or off,
# then checks:
#   1. the firewall's startup log: every PASS line for the mode, and no FAIL, ERROR, or FATAL
#   2. the in-container audit rows, through run-audit.bash against expected/ci-ipv6-<mode>.tsv
#   3. with IPv6 on: the firewall refuses to start without ip6tables, with a global IPv6 address and with
#      only a link-local one
#
# Runs in CI (.github/workflows/firewall-tests.yml) and on a developer machine with Docker. Uses the images
# named by FWTEST_BASE_IMAGE and FWTEST_PROXY_IMAGE, default agent-sandbox-base:local and
# agent-sandbox-proxy:local, as built by ./images/build.sh base and ./images/build.sh proxy.
#
# Usage: images/base/tests/firewall-e2e.bash --ipv6 on|off [--keep] [--out DIR]
#   --keep     leave the stack running afterwards, for debugging
#   --out DIR  where the audit writes its results (default: a temporary directory)
# Exits 0 when every check passes, 1 otherwise. Under GitHub Actions a failure is also reported as up to four
# error annotations (the failed checks, the mismatched audit rows, and the agent and proxy log tails), which the
# GitHub API serves without the job log.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
MODE=""
KEEP=0
OUT=""

while [ $# -gt 0 ]; do
  case $1 in
    --ipv6) MODE=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --out) OUT=$2; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case $MODE in
  on|off) ;;
  *) echo "usage: $0 --ipv6 on|off [--keep] [--out DIR]" >&2; exit 2 ;;
esac

PROJECT="fwtest-ipv6-$MODE"
FILES=(-f "$SCRIPT_DIR/firewall-e2e.compose.yml")
FAILURES=0
FAIL_MESSAGES=()
VERSIONS=""
[ -n "$OUT" ] || OUT=$(mktemp -d)

log() { printf '[fwtest %s] %s\n' "$MODE" "$*"; }
fail() {
  printf '[fwtest %s] FAIL: %s\n' "$MODE" "$*"
  FAILURES=$((FAILURES + 1))
  FAIL_MESSAGES+=("$*")
}

# annotate TITLE TEXT: a GitHub Actions error annotation, when running there. Workflow commands need %, CR, and LF
# escaped. GitHub keeps ten error annotations per step, so callers keep to a handful.
annotate() {
  [ "${GITHUB_ACTIONS:-}" = true ] || return 0
  local text=$2
  text=${text//'%'/'%25'}
  text=${text//$'\r'/'%0D'}
  text=${text//$'\n'/'%0A'}
  printf '::error title=firewall-e2e (IPv6 %s) %s::%s\n' "$MODE" "$1" "$text"
}
compose() { docker compose -p "$PROJECT" "${FILES[@]}" "$@"; }

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    log "--keep: leaving project $PROJECT running; remove it with: docker compose -p $PROJECT down -v"
    return
  fi
  compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

dump_logs() {
  log "agent log:"; compose logs --no-color agent 2>&1 | sed 's/^/    /' || true
  log "proxy log (tail):"; compose logs --no-color --tail 40 proxy 2>&1 | sed 's/^/    /' || true
}

# finish_failed: print the logs, report the failure as annotations, and exit 1.
finish_failed() {
  trap - ERR
  dump_logs
  local failed mismatches compare
  failed=$(printf -- '- %s\n' "${FAIL_MESSAGES[@]}")
  annotate "failed checks" "$FAILURES check(s) failed ($VERSIONS):"$'\n'"$failed"
  compare=$(ls -t "$OUT"/*/compare.tsv 2>/dev/null | head -n 1 || true)
  if [ -n "$compare" ]; then
    mismatches=$(awk -F'\t' '$2 == "MISMATCH" || $2 == "MISSING" || ($2 == "SKIPPED" && $3 != "*") {
      printf "%s %s expected=%s observed=%s %s\n", $1, $2, $3, $4, substr($5, 1, 100) }' "$compare")
    [ -z "$mismatches" ] || annotate "audit rows" "$mismatches"
  fi
  annotate "agent log" "$(compose logs --no-color --no-log-prefix --tail 40 agent 2>&1 || true)"
  annotate "proxy log" "$(compose logs --no-color --no-log-prefix --tail 25 proxy 2>&1 || true)"
  log "$FAILURES check(s) failed; audit results under $OUT"
  exit 1
}

# Under set -e an unexpected command failure would end the run with no report; record it and report as usual.
on_unexpected_error() { # LINE COMMAND
  fail "unexpected error at line $1: $2"
  finish_failed
}
trap 'on_unexpected_error "$LINENO" "$BASH_COMMAND"' ERR

server_version=$(docker version --format '{{.Server.Version}}')
VERSIONS="docker engine $server_version, compose $(docker compose version --short 2>/dev/null || echo '?'), kernel $(uname -r)"
log "$VERSIONS"
log "images: ${FWTEST_BASE_IMAGE:-agent-sandbox-base:local} ${FWTEST_PROXY_IMAGE:-agent-sandbox-proxy:local}"
if [ "$MODE" = on ]; then
  FILES+=(-f "$SCRIPT_DIR/firewall-e2e.ipv6.yml")
  # Engines before 27 do not assign an IPv6 prefix on their own.
  if [ "${server_version%%.*}" -lt 27 ] 2>/dev/null; then
    FILES+=(-f "$SCRIPT_DIR/firewall-e2e.ipv6-subnet.yml")
    log "engine before 27: declaring the IPv6 subnet"
  fi
fi

# --- start ----------------------------------------------------------------
compose down -v --remove-orphans >/dev/null 2>&1 || true
log "starting $PROJECT"
if ! up_output=$(compose up -d 2>&1); then
  printf '%s\n' "$up_output"
  fail "docker compose up failed: $(printf '%s' "$up_output" | tail -n 5)"
  finish_failed
fi
printf '%s\n' "$up_output"
AGENT=$(compose ps -aq agent)
[ -n "$AGENT" ] || { fail "no agent container"; finish_failed; }

# The firewall runs once, at start. Wait for it to finish one way or the other.
agent_log=""
for _ in $(seq 1 120); do
  agent_log=$(compose logs --no-color --no-log-prefix agent 2>&1 || true)
  case $agent_log in
    *"Firewall initialization complete."*|*"FATAL: Firewall initialization failed!"*) break ;;
  esac
  if [ "$(docker inspect -f '{{.State.Running}}' "$AGENT" 2>/dev/null)" != true ]; then
    break
  fi
  sleep 1
done

# --- 1. startup log ---------------------------------------------------------
expect_line() { # TEXT
  case $agent_log in
    *"$1"*) log "ok: $1" ;;
    *) fail "startup log lacks: $1" ;;
  esac
}
expect_line "OK (proxy resolves to"
expect_line "PASS: unknown name refused with NXDOMAIN"
expect_line "PASS: Docker's resolver at 127.0.0.11 refused"
expect_line "PASS: Direct outbound blocked (1.1.1.1 unreachable)"
if [ "$MODE" = on ]; then
  expect_line "IPv6: present on eth0"
  expect_line "PASS: IPv6 UDP/53 to a public resolver rejected"
  expect_line "PASS: IPv6 TCP/53 to a public resolver rejected"
  expect_line "PASS: IPv6 loopback open (::1)"
else
  expect_line "IPv6: absent on eth0"
  expect_line "PASS: IPv6 absent on eth0"
fi
expect_line "Firewall initialization complete."
if printf '%s\n' "$agent_log" | grep -Eq '^(FAIL|ERROR)|FATAL'; then
  fail "startup log has a FAIL, ERROR, or FATAL line"
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$AGENT")" != true ]; then
  fail "agent container is not running; skipping the audit"
  finish_failed
fi

# --- 2. audit rows ------------------------------------------------------------
log "running the audit, stage ci-ipv6-$MODE"
audit_rc=0
"$REPO_ROOT/scripts/dns-egress-audit/run-audit.bash" \
  --container "$AGENT" --stage "ci-ipv6-$MODE" --policy-probes --skip-vm --out "$OUT" || audit_rc=$?
if [ "$audit_rc" -ne 0 ]; then
  fail "audit exited $audit_rc (1: a row did not match, 2: the audit could not run, 3: an expected row was skipped)"
fi

# --- 3. fail closed without ip6tables (IPv6 on only) ----------------------------
root() { docker exec -u root "$AGENT" "$@"; }
if [ "$MODE" = on ]; then
  log "checking that the firewall refuses to start without ip6tables"
  root mv /usr/sbin/ip6tables /usr/sbin/ip6tables.off

  out=$(root /usr/local/bin/init-firewall.sh 2>&1) && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ERROR: IPv6 is present (eth0 "; then
    log "ok: refused with a global IPv6 address"
  else
    fail "firewall started without ip6tables with a global IPv6 address (exit $rc): $(printf '%s' "$out" | tail -n 3)"
  fi

  global=$(root ip -6 addr show dev eth0 scope global | awk '/inet6/ { print $2; exit }')
  gateway=$(root ip -6 route show default | awk '{ print $3; exit }')
  root ip -6 addr del "$global" dev eth0
  out=$(root /usr/local/bin/init-firewall.sh 2>&1) && rc=0 || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ERROR: IPv6 is present (eth0 fe80:"; then
    log "ok: refused with only a link-local IPv6 address"
  else
    fail "firewall started without ip6tables with a link-local IPv6 address (exit $rc): $(printf '%s' "$out" | tail -n 3)"
  fi

  root ip -6 addr add "$global" dev eth0
  if [ -n "$gateway" ] && ! root ip -6 route show default | grep -q .; then
    root ip -6 route add default via "$gateway" dev eth0
  fi
  root mv /usr/sbin/ip6tables.off /usr/sbin/ip6tables
  out=$(root /usr/local/bin/init-firewall.sh 2>&1) && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "Firewall initialization complete."; then
    log "ok: firewall starts again once ip6tables is back"
  else
    fail "firewall did not recover after restoring ip6tables (exit $rc): $(printf '%s' "$out" | tail -n 3)"
  fi
fi

# --- summary --------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  finish_failed
fi
log "all checks passed; audit results under $OUT"
