#!/usr/bin/env bash
# DNS egress audit probes for m18. Runs inside the agent container.
#
# Needs only bash, coreutils, iproute2, and curl, so it runs unchanged in
# every agent image. DNS packets are built by hand and sent through bash's
# /dev/udp and /dev/tcp redirections because the images carry no dig, nc,
# or python.
#
# Output: one TSV line per probe on stdout: id, target, result, detail.
# Result vocabulary:
#   answered        a DNS reply with at least one answer record
#   noerror-empty   a DNS reply with NOERROR and no answers
#   nxdomain        a DNS reply with RCODE 3
#   servfail        a DNS reply with RCODE 2
#   dns-refused     a DNS reply with RCODE 5
#   reached         the peer listener replied, so port 53 to that address is open
#   rejected        the firewall's REJECT: EPERM on a UDP send or EHOSTUNREACH on a TCP connect
#   conn-refused    the address is reachable and nothing listens there
#   unreachable     no route, which today means IPv6 is absent
#   timeout         no reply and no error, a silent drop or a listener that never answers
#   proxy-403       the proxy refused the request by policy
#   http-<code>     any other HTTP status through the proxy
#   curl-<exit>     curl failed before getting a status
#   present/absent  for the IPv6 presence probe
#   info            informational rows that are recorded, not compared
set -u

ZONE=example.com
LABEL=""
PEER=""
PROXY="${HTTPS_PROXY:-http://proxy:8080}"
ONLY=""
POLICY_PROBES=0
TIMEOUT=3
LIST=0

usage() {
  cat <<'USAGE'
Usage: probe.bash [--label STR] [--zone DOMAIN] [--peer ADDR] [--proxy URL]
                  [--only ID[,ID...]] [--policy-probes] [--timeout SECS] [--list]

  --label STR      Random label to query under the zone. Default: 8 random hex chars.
                   The host-side capture greps for this value.
  --zone DOMAIN    Public zone the random label is queried under. Default: example.com.
  --peer ADDR      Address of the dns-peer listener on the compose network. Enables B3 and B4.
  --proxy URL      Proxy for the D probes. Default: HTTPS_PROXY or http://proxy:8080.
  --only IDS       Run only these probe ids.
  --policy-probes  Also run D2, D3, and D4, which need temporary policy entries.
  --timeout SECS   Reply wait per probe. Default: 3.
  --list           Print the probe table and exit.
USAGE
}

# id|target|description
PROBES=(
  "R1|/etc/resolv.conf|stub resolver configuration Docker wrote into the container"
  "R2|ip route|default route and host network"
  "A1|127.0.0.11|libc stub, public name: getent ahosts ZONE"
  "A2|127.0.0.11|libc stub, random label: getent ahosts LABEL.ZONE"
  "A3|127.0.0.11:53/udp|raw UDP query, A ZONE"
  "A4|127.0.0.11:53/udp|raw UDP query, TXT ZONE"
  "A5|127.0.0.11:53/udp|raw UDP query, NULL ZONE"
  "A6|127.0.0.11:53/udp|raw UDP query, A on a 253-byte name under ZONE"
  "A7|127.0.0.11:53/tcp|raw TCP query, A ZONE"
  "A8|127.0.0.11:53/udp|raw UDP query, A proxy (compose service name)"
  "B1|gateway:53/udp|raw UDP query to the Docker bridge gateway"
  "B2|gateway:53/tcp|raw TCP query to the Docker bridge gateway"
  "B3|peer:53/udp|raw UDP query to a peer container on the compose network"
  "B4|peer:53/tcp|raw TCP query to a peer container on the compose network"
  "C1|upstream:53/udp|raw UDP query to the embedded resolver's upstream"
  "C2|upstream:53/tcp|raw TCP query to the embedded resolver's upstream"
  "C3|8.8.8.8:53/udp|raw UDP query to a public resolver"
  "C4|8.8.8.8:53/tcp|raw TCP query to a public resolver"
  "C5|1.1.1.1:853/tcp|DNS-over-TLS port to a public resolver"
  "D1|dns.google via proxy|DNS-over-HTTPS through the proxy to an unlisted host"
  "D2|dns.google via proxy|DNS-over-HTTPS through the proxy with the host temporarily allowed"
  "D3|proxy:9 via proxy|allowed name that resolves into the sandbox's own bridge network"
  "D4|localhost:9 via proxy|allowed name that resolves to the proxy's loopback"
  "E1|ip -6|IPv6 address and default route on eth0"
  "E2|[2001:4860:4860::8888]:53/udp|raw UDP query to a public resolver over IPv6"
  "E3|[2001:4860:4860::8888]:53/tcp|raw TCP query to a public resolver over IPv6"
  "E4|[2606:4700:4700::1111]:853/tcp|DNS-over-TLS port over IPv6"
  "E5|[::1]:53/udp|raw UDP query to IPv6 loopback"
)

while [ $# -gt 0 ]; do
  case $1 in
    --label) LABEL=$2; shift 2 ;;
    --zone) ZONE=$2; shift 2 ;;
    --peer) PEER=$2; shift 2 ;;
    --proxy) PROXY=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    --policy-probes) POLICY_PROBES=1; shift ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$LIST" -eq 1 ]; then
  printf 'id\ttarget\tdescription\n'
  for row in "${PROBES[@]}"; do
    IFS='|' read -r id target desc <<<"$row"
    printf '%s\t%s\t%s\n' "$id" "$target" "$desc"
  done
  exit 0
fi

[ -n "$LABEL" ] || LABEL=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
ERRF=$(mktemp)
trap 'rm -f "$ERRF"' EXIT

GATEWAY=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')
UPSTREAM=$(sed -n 's/.*ExtServers: \[\(.*\)\].*/\1/p' /etc/resolv.conf | sed 's/host(\(.*\))/\1/' | cut -d, -f1 | tr -d ' ')

selected() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; esac
  return 1
}

sanitize() { tr '\t\n' '  ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c1-200; }

emit() { # id target result detail
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(printf '%s' "$4" | sanitize)"
}

hexdump_bin() { od -An -v -tx1 | tr -d ' \n'; }

# build_query NAME QTYPE: write a DNS query packet (id 0x1234, RD set) to stdout
build_query() {
  local name=$1 qtype=$2 out='\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00' label
  local IFS=.
  for label in $name; do
    out+=$(printf '\\x%02x' "${#label}")
    out+=$(printf '%s' "$label" | od -An -v -tx1 | tr -d ' \n' | sed 's/../\\x&/g')
  done
  out+='\x00'
  out+=$(printf '\\x%02x\\x%02x' $((qtype >> 8)) $((qtype & 255)))
  out+='\x00\x01'
  # shellcheck disable=SC2059
  printf "$out"
}

# errno_result TEXT: map an errno message from bash to a result word
errno_result() {
  case $1 in
    *"Operation not permitted"*) echo rejected ;;
    *"No route to host"*) echo rejected ;;
    *"Connection refused"*) echo conn-refused ;;
    *"Network is unreachable"*) echo unreachable ;;
    *"timed out"*) echo timeout ;;
    "") echo timeout ;;
    *) echo error ;;
  esac
}

last_errno() { printf '%s' "$1" | tail -n1 | sed 's/.*: //'; }

# parse_reply HEX: print "result detail" for a DNS reply
parse_reply() {
  local hex=$1 rc an bytes
  bytes=$(( ${#hex} / 2 ))
  if [ ${#hex} -lt 24 ]; then echo "error short reply, $bytes bytes"; return; fi
  rc=$(( 16#${hex:6:2} & 15 ))
  an=$(( 16#${hex:12:4} ))
  case $rc in
    0) if [ "$an" -gt 0 ]; then echo "answered answers=$an bytes=$bytes"; else echo "noerror-empty bytes=$bytes"; fi ;;
    2) echo "servfail bytes=$bytes" ;;
    3) echo "nxdomain bytes=$bytes" ;;
    5) echo "dns-refused bytes=$bytes" ;;
    *) echo "rcode$rc bytes=$bytes" ;;
  esac
}

# dns_udp HOST PORT NAME QTYPE: print "result detail"
dns_udp() {
  local host=$1 port=$2 name=$3 qtype=$4 err hex
  # Open in this shell, not a subshell, so fd 3 survives; capture stderr via a file.
  { exec 3<>"/dev/udp/$host/$port"; } 2>"$ERRF"
  err=$(<"$ERRF")
  if [ -n "$err" ]; then echo "$(errno_result "$err") $(last_errno "$err")"; return; fi
  { build_query "$name" "$qtype" >&3; } 2>"$ERRF"
  err=$(<"$ERRF")
  if [ -n "$err" ]; then exec 3>&- 3<&-; echo "$(errno_result "$err") $(last_errno "$err")"; return; fi
  hex=$(timeout "$TIMEOUT" dd bs=4096 count=1 2>/dev/null <&3 | hexdump_bin)
  if [ -z "$hex" ]; then
    # A second send surfaces an ICMP error queued on the connected socket.
    { build_query "$name" "$qtype" >&3; } 2>"$ERRF"
    err=$(<"$ERRF")
    exec 3>&- 3<&-
    echo "$(errno_result "$err") $(last_errno "$err")"
    return
  fi
  exec 3>&- 3<&-
  parse_reply "$hex"
}

# tcp_connect HOST PORT: print "" on success or "result detail" on failure
tcp_connect() {
  local host=$1 port=$2 err rc
  err=$(timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>&1); rc=$?
  if [ "$rc" -eq 124 ]; then echo "timeout connect timed out after ${TIMEOUT}s"; return; fi
  if [ "$rc" -ne 0 ]; then echo "$(errno_result "$err") $(last_errno "$err")"; return; fi
  echo ""
}

# dns_tcp HOST PORT NAME QTYPE: print "result detail"
dns_tcp() {
  local host=$1 port=$2 name=$3 qtype=$4 fail hex len
  fail=$(tcp_connect "$host" "$port")
  if [ -n "$fail" ]; then echo "$fail"; return; fi
  if ! { exec 3<>"/dev/tcp/$host/$port"; } 2>/dev/null; then echo "error second connect failed"; return; fi
  len=$(( $(build_query "$name" "$qtype" | hexdump_bin | wc -c) / 2 ))
  { printf "$(printf '\\x%02x\\x%02x' $((len >> 8)) $((len & 255)))"; build_query "$name" "$qtype"; } >&3 2>/dev/null
  hex=$(timeout "$TIMEOUT" dd bs=4096 count=1 2>/dev/null <&3 | hexdump_bin)
  exec 3>&- 3<&-
  if [ -z "$hex" ]; then echo "timeout connected, no reply"; return; fi
  parse_reply "${hex:4}"
}

# port_open HOST PORT: print "reached" or the failure result
port_open() {
  local fail
  fail=$(tcp_connect "$1" "$2")
  if [ -z "$fail" ]; then echo "reached tcp connect succeeded"; else echo "$fail"; fi
}

# peer_result "result detail": any DNS reply from the peer means the port is open
peer_result() {
  case $1 in
    answered*|noerror-empty*|nxdomain*|servfail*|dns-refused*|rcode*) echo "reached ${1#* }" ;;
    *) echo "$1" ;;
  esac
}

# http_probe URL: print "result detail"
http_probe() {
  local url=$1 body code connect rc
  body=$(mktemp)
  # --noproxy '' overrides the container's NO_PROXY list, which names proxy and localhost; D3 and D4 must go
  # through the proxy even though they target those names.
  code=$(curl -s -m 10 --noproxy '' -o "$body" -w '%{http_code} %{http_connect}' -x "$PROXY" "$url" 2>/dev/null); rc=$?
  connect=${code#* }; code=${code%% *}
  if [ "$connect" = 403 ] || { [ "$code" = 403 ] && grep -q "Blocked by proxy policy" "$body"; }; then
    echo "proxy-403 $(head -c 120 "$body")"
  elif [ "$rc" -ne 0 ]; then
    echo "curl-$rc connect=$connect"
  else
    echo "http-$code $(head -c 120 "$body")"
  fi
  rm -f "$body"
}

getent_result() { # NAME
  local out rc
  out=$(getent ahosts "$1" 2>&1); rc=$?
  case $rc in
    0) echo "answered $(printf '%s' "$out" | awk 'NR==1{print $1}')" ;;
    2) echo "not-found getent rc=2" ;;
    *) echo "error getent rc=$rc $out" ;;
  esac
}

split() { # "result detail" -> RESULT and DETAIL globals
  RESULT=${1%% *}
  DETAIL=${1#"$RESULT"}
  DETAIL=${DETAIL# }
}

run() { # id target "result detail"
  split "$3"
  emit "$1" "$2" "$RESULT" "$DETAIL"
}

LONG_LABEL=$(printf '%s' "$LABEL$LABEL$LABEL$LABEL$LABEL$LABEL$LABEL$LABEL" | cut -c1-63)
# 4 labels of 63 plus "example.com" would exceed 253, so size the last label to fit.
LONG_TAIL_LEN=$(( 253 - 3 * 64 - ${#ZONE} - 1 ))
LONG_NAME="$LONG_LABEL.$LONG_LABEL.$LONG_LABEL.$(printf '%s' "$LONG_LABEL" | cut -c1-"$LONG_TAIL_LEN").$ZONE"

selected R1 && emit R1 /etc/resolv.conf info "$(grep -E 'nameserver|ExtServers|Overrides|options' /etc/resolv.conf)"
selected R2 && emit R2 "ip route" info "gateway=$GATEWAY upstream=${UPSTREAM:-none} $(ip -4 route show | tr '\n' ';')"

selected A1 && run A1 "127.0.0.11" "$(getent_result "$ZONE")"
selected A2 && run A2 "127.0.0.11" "$(getent_result "$LABEL.$ZONE")"
selected A3 && run A3 "127.0.0.11:53/udp" "$(dns_udp 127.0.0.11 53 "$ZONE" 1)"
selected A4 && run A4 "127.0.0.11:53/udp" "$(dns_udp 127.0.0.11 53 "$ZONE" 16)"
selected A5 && run A5 "127.0.0.11:53/udp" "$(dns_udp 127.0.0.11 53 "$ZONE" 10)"
selected A6 && run A6 "127.0.0.11:53/udp" "$(dns_udp 127.0.0.11 53 "$LONG_NAME" 1)"
selected A7 && run A7 "127.0.0.11:53/tcp" "$(dns_tcp 127.0.0.11 53 "$ZONE" 1)"
selected A8 && run A8 "127.0.0.11:53/udp" "$(dns_udp 127.0.0.11 53 proxy 1)"

if [ -n "$GATEWAY" ]; then
  selected B1 && run B1 "$GATEWAY:53/udp" "$(dns_udp "$GATEWAY" 53 "$ZONE" 1)"
  selected B2 && run B2 "$GATEWAY:53/tcp" "$(dns_tcp "$GATEWAY" 53 "$ZONE" 1)"
else
  selected B1 && emit B1 "gateway:53/udp" error "no default route"
  selected B2 && emit B2 "gateway:53/tcp" error "no default route"
fi
if [ -n "$PEER" ]; then
  selected B3 && run B3 "$PEER:53/udp" "$(peer_result "$(dns_udp "$PEER" 53 "$LABEL.$ZONE" 1)")"
  selected B4 && run B4 "$PEER:53/tcp" "$(peer_result "$(dns_tcp "$PEER" 53 "$LABEL.$ZONE" 1)")"
fi

if [ -n "$UPSTREAM" ]; then
  selected C1 && run C1 "$UPSTREAM:53/udp" "$(dns_udp "$UPSTREAM" 53 "$ZONE" 1)"
  selected C2 && run C2 "$UPSTREAM:53/tcp" "$(dns_tcp "$UPSTREAM" 53 "$ZONE" 1)"
else
  selected C1 && emit C1 "upstream:53/udp" error "no ExtServers line in resolv.conf"
  selected C2 && emit C2 "upstream:53/tcp" error "no ExtServers line in resolv.conf"
fi
selected C3 && run C3 "8.8.8.8:53/udp" "$(dns_udp 8.8.8.8 53 "$ZONE" 1)"
selected C4 && run C4 "8.8.8.8:53/tcp" "$(dns_tcp 8.8.8.8 53 "$ZONE" 1)"
selected C5 && run C5 "1.1.1.1:853/tcp" "$(port_open 1.1.1.1 853)"

selected D1 && run D1 "dns.google via proxy" "$(http_probe "https://dns.google/resolve?name=$LABEL.$ZONE&type=A")"
if [ "$POLICY_PROBES" -eq 1 ]; then
  selected D2 && run D2 "dns.google via proxy" "$(http_probe "https://dns.google/resolve?name=$LABEL.$ZONE&type=A")"
  selected D3 && run D3 "proxy:9 via proxy" "$(http_probe "http://proxy:9/")"
  selected D4 && run D4 "localhost:9 via proxy" "$(http_probe "http://localhost:9/")"
fi

V6_ADDR=$(ip -6 addr show dev eth0 scope global 2>/dev/null | awk '/inet6/{print $2}' | tr '\n' ' ')
V6_ROUTE=$(ip -6 route show default 2>/dev/null | tr '\n' ' ')
if [ -n "$V6_ADDR" ]; then
  selected E1 && emit E1 "ip -6" present "addr=$V6_ADDR route=${V6_ROUTE:-none}"
else
  selected E1 && emit E1 "ip -6" absent "no global IPv6 address on eth0; route=${V6_ROUTE:-none}"
fi
selected E2 && run E2 "[2001:4860:4860::8888]:53/udp" "$(dns_udp 2001:4860:4860::8888 53 "$ZONE" 1)"
selected E3 && run E3 "[2001:4860:4860::8888]:53/tcp" "$(dns_tcp 2001:4860:4860::8888 53 "$ZONE" 1)"
selected E4 && run E4 "[2606:4700:4700::1111]:853/tcp" "$(port_open 2606:4700:4700::1111 853)"
selected E5 && run E5 "[::1]:53/udp" "$(dns_udp ::1 53 "$ZONE" 1)"
