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
# Exits 0 when every check passes, 1 otherwise.
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
[ -n "$OUT" ] || OUT=$(mktemp -d)

log() { printf '[fwtest %s] %s\n' "$MODE" "$*"; }
fail() { printf '[fwtest %s] FAIL: %s\n' "$MODE" "$*"; FAILURES=$((FAILURES + 1)); }
compose() { docker compose -p "$PROJECT" "${FILES[@]}" "$@"; }

server_version=$(docker version --format '{{.Server.Version}}')
log "docker engine $server_version, $(docker compose version --short 2>/dev/null || echo 'compose ?')"
log "images: ${FWTEST_BASE_IMAGE:-agent-sandbox-base:local} ${FWTEST_PROXY_IMAGE:-agent-sandbox-proxy:local}"
if [ "$MODE" = on ]; then
  FILES+=(-f "$SCRIPT_DIR/firewall-e2e.ipv6.yml")
  # Engines before 27 do not assign an IPv6 prefix on their own.
  if [ "${server_version%%.*}" -lt 27 ] 2>/dev/null; then
    FILES+=(-f "$SCRIPT_DIR/firewall-e2e.ipv6-subnet.yml")
    log "engine before 27: declaring the IPv6 subnet"
  fi
fi

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

# --- start ----------------------------------------------------------------
compose down -v --remove-orphans >/dev/null 2>&1 || true
log "starting $PROJECT"
compose up -d
AGENT=$(compose ps -aq agent)
[ -n "$AGENT" ] || { fail "no agent container"; dump_logs; exit 1; }

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
  dump_logs
  exit 1
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
  dump_logs
  log "$FAILURES check(s) failed; audit results under $OUT"
  exit 1
fi
log "all checks passed; audit results under $OUT"
