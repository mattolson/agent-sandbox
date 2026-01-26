#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Proxy-gatekeeper firewall
#
# Blocks all direct outbound traffic. Only the Docker host network is allowed,
# which includes the proxy sidecar container. All HTTP/HTTPS must go through
# the proxy, which handles domain-level enforcement.
#
# Allowed:
#   - Loopback (localhost, Docker DNS at 127.0.0.11)
#   - Docker host network (proxy container, other compose services)
#   - Established/related return traffic
#
# Blocked:
#   - All direct outbound (including SSH)
#   - All inbound except established connections and host network

echo "Initializing proxy-gatekeeper firewall..."

# 1. Extract Docker DNS NAT rules BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# 2. Flush all existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 3. Restore Docker internal DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# 4. Allow loopback (covers Docker DNS at 127.0.0.11)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 5. Detect and allow Docker host network (where proxy container lives)
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

# 6. Allow established/related connections (return traffic)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 7. Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 8. Reject remaining outbound with ICMP for immediate feedback
#    (instead of silent DROP which causes timeouts)
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configured."
echo ""
echo "Verifying..."

# Negative test: direct outbound should be blocked
if curl --connect-timeout 3 --noproxy '*' https://example.com >/dev/null 2>&1; then
    echo "ERROR: Verification failed - direct connection to example.com succeeded"
    exit 1
else
    echo "  PASS: Direct outbound blocked (example.com unreachable)"
fi

# Positive test: host network gateway should be reachable
GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
if ping -c 1 -W 3 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo "  PASS: Host network reachable ($GATEWAY_IP)"
else
    echo "  WARN: Host network gateway not responding to ping (may be normal)"
fi

echo ""
echo "Firewall initialization complete."
