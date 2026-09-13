#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Proxy-gatekeeper firewall
#
# Blocks all direct outbound traffic. Only the Docker host network is allowed,
# which includes the proxy sidecar container. All HTTP/HTTPS must go through
# the proxy, which handles domain-level enforcement, and all name resolution
# goes to the proxy's DNS sinkhole, which answers compose service names and
# refuses everything else.
#
# Allowed:
#   - Loopback, except Docker's embedded resolver at 127.0.0.11
#   - DNS to the proxy's sinkhole only; port 53 to the proxy is rewritten to it
#   - Docker host network (proxy container, other compose services)
#   - Established/related return traffic
#
# Blocked:
#   - Docker's embedded resolver, on port 53 and on its real listening port
#   - DNS (53) and DNS-over-TLS (853) to anything but the sinkhole
#   - All other direct outbound (including SSH)
#   - All inbound except established connections and host network

SINKHOLE_PORT=5353
RESOLV_CONF=/etc/resolv.conf

echo "Initializing proxy-gatekeeper firewall..."

# write_resolv_conf ADDRESS: point the stub resolver at ADDRESS.
# /etc/resolv.conf is a bind mount, so it is truncated and rewritten in place.
# A rename would fail on the mount and a copy would be invisible to it.
write_resolv_conf() {
    local address=$1 keep
    keep=$(grep -E '^(search|options) ' "$RESOLV_CONF" 2>/dev/null || true)
    {
        echo "# Managed by init-firewall.sh (agentbox). Names resolve only through the proxy's DNS sinkhole."
        echo "nameserver $address"
        if [ -n "$keep" ]; then
            printf '%s\n' "$keep"
        fi
    } > "$RESOLV_CONF"
}

# resolve_proxy: print the proxy service's IPv4 address, or nothing.
resolve_proxy() {
    getent hosts proxy 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1; exit }'
}

# dns_rcode HOST PORT NAME: send one A query with bash sockets and print the
# reply's RCODE, or "timeout". Used by the self-test so it can tell a refusal
# (NXDOMAIN) from a resolver that hangs or forwards.
dns_rcode() {
    local host=$1 port=$2 name=$3 label out hex
    out='\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00'
    local IFS=.
    for label in $name; do
        out+=$(printf '\\x%02x' "${#label}")
        out+=$(printf '%s' "$label" | od -An -v -tx1 | tr -d ' \n' | sed 's/../\\x&/g')
    done
    out+='\x00\x00\x01\x00\x01'
    if ! { exec 3<>"/dev/udp/$host/$port"; } 2>/dev/null; then
        echo "unreachable"
        return
    fi
    # shellcheck disable=SC2059
    printf "$out" >&3 2>/dev/null || { exec 3>&- 3<&-; echo "rejected"; return; }
    hex=$(timeout 3 dd bs=512 count=1 2>/dev/null <&3 | od -An -v -tx1 | tr -d ' \n')
    exec 3>&- 3<&-
    if [ -z "$hex" ]; then
        echo "timeout"
    else
        echo $(( 16#${hex:6:2} & 15 ))
    fi
}

# 1. Learn the proxy's address before touching any rule.
#    On a fresh network namespace Docker's DNS NAT rules exist and the embedded
#    resolver at 127.0.0.11 answers. After a container restart Docker leaves a
#    modified resolv.conf alone but the namespace is fresh, so point the stub at
#    127.0.0.11 for this one lookup whenever Docker's rules are present.
if iptables-save -t nat 2>/dev/null | grep -q "127\.0\.0\.11"; then
    write_resolv_conf 127.0.0.11
fi
PROXY_IP=$(resolve_proxy || true)
if [ -z "$PROXY_IP" ]; then
    echo "ERROR: cannot resolve the proxy service through the current resolver."
    echo "       Is the proxy container running? If it was recreated, restart the agent container."
    exit 1
fi
echo "Proxy address: $PROXY_IP"

# 2. Flush all existing rules, including Docker's DNS NAT redirect, which is
#    deliberately not restored: the embedded resolver forwards every unknown
#    name to the host and out to the internet.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 3. Docker's embedded resolver stays bound to 127.0.0.11 on a random port, and
#    the NAT rule was only ever a redirect to it. Reject the address outright,
#    ahead of the loopback rule, so neither port 53 nor the real port is reachable.
iptables -A OUTPUT -d 127.0.0.11 -j REJECT --reject-with icmp-admin-prohibited

# 4. Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 5. DNS goes only to the proxy's sinkhole. The stub resolver sends to port 53,
#    which is rewritten to the sinkhole port on the proxy; anything else on 53
#    or 853, including peers on the host network, is rejected before rule 6.
iptables -t nat -A OUTPUT -d "$PROXY_IP" -p udp --dport 53 -j DNAT --to-destination "$PROXY_IP:$SINKHOLE_PORT"
iptables -t nat -A OUTPUT -d "$PROXY_IP" -p tcp --dport 53 -j DNAT --to-destination "$PROXY_IP:$SINKHOLE_PORT"
iptables -A OUTPUT -d "$PROXY_IP" -p udp --dport "$SINKHOLE_PORT" -j ACCEPT
iptables -A OUTPUT -d "$PROXY_IP" -p tcp --dport "$SINKHOLE_PORT" -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp --dport 53 -j REJECT --reject-with icmp-admin-prohibited
iptables -A OUTPUT -p tcp --dport 853 -j REJECT --reject-with icmp-admin-prohibited

# 6. Detect and allow Docker host network (where proxy container lives)
# Extract network CIDR from the route table instead of assuming /24
DEFAULT_IF=$(ip route | grep default | awk '{print $5}')
HOST_NETWORK=$(ip route | grep -E "^[0-9].*dev $DEFAULT_IF" | grep -v default | awk '{print $1}' | head -1)
if [ -z "$HOST_NETWORK" ]; then
    echo "ERROR: Failed to detect host network from route table"
    exit 1
fi
echo "Host network: $HOST_NETWORK"

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# 7. Allow established/related connections (return traffic)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 8. Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 9. Reject remaining outbound with ICMP for immediate feedback
#    (instead of silent DROP which causes timeouts)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 10. Point the stub resolver at the proxy. From here on every lookup in this
#     container goes to the sinkhole.
write_resolv_conf "$PROXY_IP"

echo "Firewall configured."
echo ""

# DNS positive test: the proxy's name must resolve through the sinkhole
MAX_ATTEMPTS=30
ATTEMPT=1
echo -n "Waiting for the DNS sinkhole..."
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if [ "$(resolve_proxy || true)" = "$PROXY_IP" ]; then
        echo "  OK (proxy resolves to $PROXY_IP through the sinkhole)"
        break
    fi
    echo -n "."
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    echo "  FAILED"
    echo "ERROR: 'proxy' does not resolve through the sinkhole at $PROXY_IP:$SINKHOLE_PORT after ${MAX_ATTEMPTS}s."
    echo "       The proxy image may predate the DNS sinkhole. Run 'agentbox bump' and then 'agentbox up'."
    exit 1
fi

# Positive test: proxy should be reachable
ATTEMPT=1
echo -n "Waiting for proxy..."
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if curl -s --connect-timeout 1 -o /dev/null http://proxy:8080 2>/dev/null; then
        echo "  OK (proxy:8080 reachable)"
        break
    fi
    echo -n "."
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
    echo "  FAILED"
    echo "ERROR: Proxy not reachable after ${MAX_ATTEMPTS}s"
    exit 1
fi

# DNS negative test: a name the stack does not know must be refused promptly,
# with NXDOMAIN, rather than forwarded or dropped. The query goes to port 53 on
# the proxy so the rewrite in rule 5 is exercised too.
NEGATIVE_NAME="sinkhole-test-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n').invalid"
echo "Verifying the DNS sinkhole..."
RCODE=$(dns_rcode "$PROXY_IP" 53 "$NEGATIVE_NAME")
case $RCODE in
    3) echo "PASS: unknown name refused with NXDOMAIN ($NEGATIVE_NAME)" ;;
    0) echo "FAIL: $NEGATIVE_NAME was answered; the resolver is forwarding queries"; exit 1 ;;
    timeout) echo "FAIL: lookup of $NEGATIVE_NAME hung; queries are being dropped instead of refused"; exit 1 ;;
    *) echo "FAIL: lookup of $NEGATIVE_NAME returned $RCODE instead of NXDOMAIN"; exit 1 ;;
esac

# Negative test: direct outbound should be blocked. An IP literal, because names
# no longer resolve and the point is the firewall, not the resolver.
echo "Verifying firewall..."
if curl --connect-timeout 3 --noproxy '*' https://1.1.1.1 >/dev/null 2>&1; then
    echo "FAIL: Direct connection to 1.1.1.1 succeeded"
    exit 1
else
    echo "PASS: Direct outbound blocked (1.1.1.1 unreachable)"
fi

echo ""
echo "Firewall initialization complete."
