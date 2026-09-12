#!/usr/bin/env bash
# Host-side runner for the m18 DNS egress audit. Run this on the Mac, not
# inside the sandbox: it needs docker, agentbox, and optionally colima.
#
# It starts a throwaway DNS responder on the sandbox's compose network,
# streams probe.bash into the agent container, captures DNS traffic inside
# the Colima VM, collects host-side facts, and diffs the results against
# expected/<stage>.tsv. See README.md in this directory.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PROBE="$SCRIPT_DIR/probe.bash"
PEER_NAME=agentbox-dns-peer
PEER_IMAGE=python:3-alpine

STAGE=baseline
CONTAINER=""
LABEL=""
ZONE=example.com
POLICY_PROBES=0
SKIP_PEER=0
SKIP_VM=0
CAPTURE_SECS=25
PAUSE=0
OUT="$SCRIPT_DIR/results"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/dns-egress-audit/run-audit.bash [options]

  --stage NAME       baseline | after-m18.2 | after-m18.3 | after-m18.4. Picks expected/<stage>.tsv.
                     Default: baseline.
  --container ID     Probe an existing container instead of the CLI stack's agent service. Use this
                     for devcontainer mode after opening the repo in VS Code.
  --label STR        Random label queried under the zone. Default: generated. The captures grep for it.
  --zone DOMAIN      Public zone for the random label. Default: example.com.
  --policy-probes    Run D2, D3, and D4. Requires the temporary policy entries described in README.md.
  --skip-peer        Do not start the peer responder. Skips B3, B4, and H3.
  --skip-vm          Do not use colima ssh. Skips the VM capture (H1) and VM listener check (H2).
  --capture-secs N   How long the VM capture runs. Default: 25.
  --pause            Print the label and wait for Enter so a Mac-side tcpdump can be started first.
  --out DIR          Results root. Default: scripts/dns-egress-audit/results.
  -n, --dry-run      Print the steps and exit without touching anything.
  -h, --help         Show this help.
USAGE
}

log() { printf '[audit] %s\n' "$*" >&2; }
die() { printf '[audit] error: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case $1 in
    --stage) STAGE=$2; shift 2 ;;
    --container) CONTAINER=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --zone) ZONE=$2; shift 2 ;;
    --policy-probes) POLICY_PROBES=1; shift ;;
    --skip-peer) SKIP_PEER=1; shift ;;
    --skip-vm) SKIP_VM=1; shift ;;
    --capture-secs) CAPTURE_SECS=$2; shift 2 ;;
    --pause) PAUSE=1; shift ;;
    --out) OUT=$2; shift 2 ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

EXPECTED="$SCRIPT_DIR/expected/$STAGE.tsv"
[ -f "$EXPECTED" ] || die "no expected file for stage '$STAGE' at $EXPECTED"
[ -n "$LABEL" ] || LABEL=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')

MAC_IFACE=$(route -n get 8.8.8.8 2>/dev/null | awk '/interface:/{print $2}' || true)
MAC_IFACE=${MAC_IFACE:-en0}

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<DRY
Dry run. Stage: $STAGE. Label: $LABEL. Zone: $ZONE.

1. Find the agent container: ${CONTAINER:-agentbox compose ps -q agent} and its compose network.
2. Start the peer responder: docker run -d --rm --name $PEER_NAME --network <net> $PEER_IMAGE python3 -u /peer.py
3. Start the VM capture: colima ssh -- sudo timeout $CAPTURE_SECS tcpdump -ni any -l -U udp port 53
   Mac-side capture, in another terminal: sudo tcpdump -ni $MAC_IFACE -l udp port 53 | grep --line-buffered $LABEL
4. Run the probes: docker exec -i <agent> bash -s -- --label $LABEL --zone $ZONE --peer <peer ip> < probe.bash
5. Collect H1 (label in the VM capture), H2 (colima ssh -- sudo ss -Hlunp sport = :53), H3 (docker run --dns <peer>),
   H4 (docker network inspect), H5 (docker exec -u root <agent> iptables -S; ip6tables -S).
6. Diff results.tsv against $EXPECTED and write everything under $OUT/$STAGE-<timestamp>/.
DRY
  exit 0
fi

command -v docker >/dev/null || die "docker not found on PATH"
cd "$REPO_ROOT"

if [ -n "$CONTAINER" ]; then
  AGENT=$(docker inspect -f '{{.Id}}' "$CONTAINER" 2>/dev/null) || die "container '$CONTAINER' not found"
else
  command -v agentbox >/dev/null || die "agentbox not found on PATH; pass --container to target a running container"
  AGENT=$(agentbox compose ps -q agent 2>/dev/null || true)
  [ -n "$AGENT" ] || die "no running agent container; start the sandbox with 'agentbox up' first"
fi
NET=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$AGENT" | head -n1)
[ -n "$NET" ] || die "could not determine the agent container's network"
AGENT_IMAGE=$(docker inspect -f '{{.Config.Image}}' "$AGENT")

RUN_DIR="$OUT/$STAGE-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
log "stage=$STAGE label=$LABEL agent=${AGENT:0:12} image=$AGENT_IMAGE network=$NET"
log "results: $RUN_DIR"

CAPTURE_PID=""
cleanup() {
  if [ -n "$CAPTURE_PID" ]; then kill "$CAPTURE_PID" 2>/dev/null || true; fi
  docker rm -f "$PEER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

SKIPPED=""
skip() { SKIPPED="$SKIPPED,$1"; }

# --- Peer responder -------------------------------------------------------
PEER_IP=""
if [ "$SKIP_PEER" -eq 0 ]; then
  cat > "$RUN_DIR/peer.py" <<'PY'
import socket
import struct
import threading

A_RDATA = bytes([203, 0, 113, 1])  # TEST-NET-3, never routable


def parse(q):
    if len(q) < 12:
        return None
    i, labels = 12, []
    while i < len(q):
        n = q[i]
        i += 1
        if n == 0:
            break
        labels.append(q[i:i + n].decode("ascii", "replace"))
        i += n
    if i + 4 > len(q):
        return None
    qtype, _qclass = struct.unpack("!HH", q[i:i + 4])
    return ".".join(labels), qtype, q[12:i + 4]


def respond(q):
    parsed = parse(q)
    if parsed is None:
        return None, None
    name, qtype, question = parsed
    answers, ancount = b"", 0
    if qtype == 1:
        answers = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 60, 4) + A_RDATA
        ancount = 1
    elif qtype == 16:
        txt = b"dns-peer"
        rdata = bytes([len(txt)]) + txt
        answers = b"\xc0\x0c" + struct.pack("!HHIH", 16, 1, 60, len(rdata)) + rdata
        ancount = 1
    resp = q[:2] + struct.pack("!HHHHH", 0x8180, 1, ancount, 0, 0) + question + answers
    return name, resp


def udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", 53))
    print("listening udp/53", flush=True)
    while True:
        q, peer = s.recvfrom(4096)
        name, resp = respond(q)
        print(f"udp {peer[0]} {name}", flush=True)
        if resp:
            s.sendto(resp, peer)


def tcp():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 53))
    s.listen(16)
    print("listening tcp/53", flush=True)
    while True:
        c, peer = s.accept()
        try:
            hdr = c.recv(2)
            if len(hdr) == 2:
                n = struct.unpack("!H", hdr)[0]
                q = b""
                while len(q) < n:
                    chunk = c.recv(n - len(q))
                    if not chunk:
                        break
                    q += chunk
                name, resp = respond(q)
                print(f"tcp {peer[0]} {name}", flush=True)
                if resp:
                    c.sendall(struct.pack("!H", len(resp)) + resp)
        finally:
            c.close()


threading.Thread(target=udp, daemon=True).start()
tcp()
PY
  docker rm -f "$PEER_NAME" >/dev/null 2>&1 || true
  log "starting peer responder $PEER_NAME on $NET"
  docker run -d --rm --name "$PEER_NAME" --network "$NET" \
    -v "$RUN_DIR/peer.py:/peer.py:ro" "$PEER_IMAGE" python3 -u /peer.py >/dev/null
  PEER_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$PEER_NAME")
  for _ in $(seq 1 30); do
    if docker logs "$PEER_NAME" 2>&1 | grep -q 'listening tcp/53'; then break; fi
    sleep 0.5
  done
  log "peer responder at $PEER_IP"
else
  skip B3; skip B4; skip H3
fi

# --- VM capture -----------------------------------------------------------
CAPTURE=0
if [ "$SKIP_VM" -eq 0 ]; then
  if ! command -v colima >/dev/null; then
    log "colima not found; skipping the VM capture and listener check"
    SKIP_VM=1
  elif ! colima ssh -- command -v tcpdump >/dev/null 2>&1; then
    log "tcpdump is not installed in the Colima VM; skipping H1."
    log "install it with: colima ssh -- sudo apt-get update '&&' sudo apt-get install -y tcpdump"
    log "or on an Alpine VM: colima ssh -- sudo apk add tcpdump"
  else
    log "starting a ${CAPTURE_SECS}s DNS capture inside the Colima VM"
    colima ssh -- sudo timeout "$CAPTURE_SECS" tcpdump -ni any -l -U udp port 53 \
      > "$RUN_DIR/vm-capture.txt" 2> "$RUN_DIR/vm-capture.err" &
    CAPTURE_PID=$!
    CAPTURE=1
    sleep 3
  fi
fi
[ "$CAPTURE" -eq 1 ] || skip H1
[ "$SKIP_VM" -eq 0 ] || skip H2

cat >&2 <<MSG

Random label for this run: $LABEL
Optional Mac-side capture, in another terminal (Ctrl-C after the run):
  sudo tcpdump -ni $MAC_IFACE -l udp port 53 | grep --line-buffered $LABEL

MSG
if [ "$PAUSE" -eq 1 ]; then
  read -r -p "Press Enter when the Mac-side capture is running... " _
fi

# --- Probes ---------------------------------------------------------------
PROBE_ARGS=(--label "$LABEL" --zone "$ZONE")
[ -n "$PEER_IP" ] && PROBE_ARGS+=(--peer "$PEER_IP")
if [ "$POLICY_PROBES" -eq 1 ]; then PROBE_ARGS+=(--policy-probes); else skip D2; skip D3; skip D4; fi
log "running probes in the agent container"
docker exec -i "$AGENT" bash -s -- "${PROBE_ARGS[@]}" < "$PROBE" > "$RUN_DIR/probes.tsv"
cp "$RUN_DIR/probes.tsv" "$RUN_DIR/results.tsv"

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(printf '%s' "$4" | tr '\t\n' '  ' | cut -c1-200)" >> "$RUN_DIR/results.tsv"; }

# --- H1: did the label leave the container? -------------------------------
if [ "$CAPTURE" -eq 1 ]; then
  log "waiting for the VM capture to finish"
  wait "$CAPTURE_PID" 2>/dev/null || true
  CAPTURE_PID=""
  hits=$(grep -c -- "$LABEL" "$RUN_DIR/vm-capture.txt" || true)
  if [ "${hits:-0}" -gt 0 ]; then
    emit H1 "vm capture" seen "$hits packets; first: $(grep -m1 -- "$LABEL" "$RUN_DIR/vm-capture.txt")"
  else
    emit H1 "vm capture" not-seen "0 packets carrying $LABEL in $(wc -l < "$RUN_DIR/vm-capture.txt" | tr -d ' ') captured lines"
  fi
fi

# --- H2: resolvers listening inside the VM --------------------------------
if [ "$SKIP_VM" -eq 0 ]; then
  {
    echo "# udp"; colima ssh -- sudo ss -Hlunp sport = :53 2>&1 || true
    echo "# tcp"; colima ssh -- sudo ss -Hltnp sport = :53 2>&1 || true
  } > "$RUN_DIR/vm-listeners.txt"
  n=$(grep -c -v '^#' "$RUN_DIR/vm-listeners.txt" || true)
  emit H2 "vm :53 listeners" info "${n:-0} sockets; $(grep -v '^#' "$RUN_DIR/vm-listeners.txt" | head -n2 | tr '\n' ';')"
fi

# --- H3: what compose dns: does on a user-defined network -----------------
if [ -n "$PEER_IP" ]; then
  docker run --rm --network "$NET" --dns "$PEER_IP" "$PEER_IMAGE" sh -c '
    cat /etc/resolv.conf
    python3 -c "import socket; print(\"proxy ->\", socket.gethostbyname(\"proxy\"))" 2>&1
    python3 -c "import socket; print(\"'"$ZONE"' ->\", socket.gethostbyname(\"'"$ZONE"'\"))" 2>&1
  ' > "$RUN_DIR/dns-override.txt" 2>&1 || true
  ns=$(awk '/^nameserver/{print $2; exit}' "$RUN_DIR/dns-override.txt")
  zone_ip=$(awk -v z="$ZONE" '$1==z {print $3}' "$RUN_DIR/dns-override.txt")
  if [ "$ns" = "127.0.0.11" ] && [ "$zone_ip" = "203.0.113.1" ]; then
    verdict=upstream-only
  elif [ "$ns" = "$PEER_IP" ]; then
    verdict=replaces-stub
  else
    verdict=info
  fi
  emit H3 "docker run --dns $PEER_IP" "$verdict" "nameserver=$ns $ZONE->${zone_ip:-?} $(grep -E 'ExtServers|proxy ->' "$RUN_DIR/dns-override.txt" | tr '\n' ' ')"
fi

# --- H4: IPv6 on the compose network --------------------------------------
emit H4 "docker network inspect $NET" info "EnableIPv6=$(docker network inspect -f '{{.EnableIPv6}}' "$NET") subnets=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$NET")"

# --- H5: firewall state as root -------------------------------------------
docker exec -u root "$AGENT" iptables -S > "$RUN_DIR/iptables.txt" 2>&1 || true
docker exec -u root "$AGENT" iptables -t nat -S >> "$RUN_DIR/iptables.txt" 2>&1 || true
docker exec -u root "$AGENT" ip6tables -S > "$RUN_DIR/ip6tables.txt" 2>&1 || true
v4=$(grep -c '^-A' "$RUN_DIR/iptables.txt" || true)
v6=$(grep -c '^-A' "$RUN_DIR/ip6tables.txt" || true)
emit H5 "iptables -S / ip6tables -S" info "ipv4 rules=${v4:-0} ipv6 rules=${v6:-0} ipv6 policy: $(grep '^-P' "$RUN_DIR/ip6tables.txt" | tr '\n' ' ' || true) $(grep -i -m1 'error\|not supported\|No such' "$RUN_DIR/ip6tables.txt" || true)"

if [ -n "$PEER_IP" ]; then docker logs "$PEER_NAME" > "$RUN_DIR/peer.log" 2>&1 || true; fi

# --- Compare --------------------------------------------------------------
awk -F'\t' -v OFS='\t' -v skipped="$SKIPPED," '
  NR == FNR { if ($0 ~ /^#/ || NF < 2) next; exp[$1] = $2; order[++n] = $1; next }
  { res[$1] = $3; det[$1] = $4 }
  END {
    for (k = 1; k <= n; k++) {
      id = order[k]
      if (exp[id] == "*") st = (id in res) ? "INFO" : "SKIPPED"
      else if (!(id in res)) st = (index(skipped, "," id ",") > 0) ? "SKIPPED" : "MISSING"
      else {
        st = "MISMATCH"; m = split(exp[id], alts, "|")
        for (i = 1; i <= m; i++) if (alts[i] == res[id]) st = "OK"
      }
      print id, st, exp[id], (id in res ? res[id] : "-"), (id in det ? det[id] : "")
    }
  }' "$EXPECTED" "$RUN_DIR/results.tsv" > "$RUN_DIR/compare.tsv"

echo
printf '%-4s %-9s %-24s %-16s %s\n' ID STATUS EXPECTED OBSERVED DETAIL
awk -F'\t' '{ printf "%-4s %-9s %-24s %-16s %s\n", $1, $2, $3, $4, substr($5, 1, 70) }' "$RUN_DIR/compare.tsv"
echo
bad=$(awk -F'\t' '$2 == "MISMATCH" || $2 == "MISSING"' "$RUN_DIR/compare.tsv" | wc -l | tr -d ' ')
log "wrote $RUN_DIR/{results,compare}.tsv plus captures and dumps"
if [ "$bad" -gt 0 ]; then
  log "$bad probe(s) did not match $STAGE expectations"
  exit 1
fi
log "all compared probes match the $STAGE expectations"
