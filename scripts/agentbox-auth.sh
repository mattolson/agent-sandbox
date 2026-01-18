#!/bin/bash
set -euo pipefail

# agentbox auth - Securely authenticate Claude Code inside a locked-down container
#
# This script temporarily relaxes the container firewall to allow the OAuth
# callback, runs `claude /login`, then re-locks the firewall.

CONTAINER_PATTERN="${1:-agent-sandbox}"
FIREWALL_RULE_COMMENT="agentbox-oauth-temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[agentbox]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[agentbox]${NC} $1"; }
log_error() { echo -e "${RED}[agentbox]${NC} $1"; }

# Find the container
find_container() {
    local container
    container=$(docker ps -q --filter "name=$CONTAINER_PATTERN" | head -n1)
    if [[ -z "$container" ]]; then
        log_error "No running container matching pattern: $CONTAINER_PATTERN"
        exit 1
    fi
    echo "$container"
}

# Check if firewall rule exists
firewall_rule_exists() {
    local container="$1"
    docker exec -u root "$container" iptables -C INPUT -j ACCEPT -m comment --comment "$FIREWALL_RULE_COMMENT" 2>/dev/null
}

# Relax firewall for OAuth
relax_firewall() {
    local container="$1"
    log_info "Relaxing firewall for OAuth callback..."
    docker exec -u root "$container" iptables -I INPUT 1 -j ACCEPT -m comment --comment "$FIREWALL_RULE_COMMENT"
}

# Re-lock firewall
lock_firewall() {
    local container="$1"
    if firewall_rule_exists "$container"; then
        log_info "Re-locking firewall..."
        docker exec -u root "$container" iptables -D INPUT -j ACCEPT -m comment --comment "$FIREWALL_RULE_COMMENT"
    fi
}

# Check if credentials exist
credentials_exist() {
    local container="$1"
    docker exec "$container" test -f /home/node/.claude/.credentials.json 2>/dev/null
}

# Cleanup on exit (ensure firewall is re-locked)
cleanup() {
    local exit_code=$?
    if [[ -n "${CONTAINER:-}" ]]; then
        lock_firewall "$CONTAINER"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main
main() {
    log_info "Finding container..."
    CONTAINER=$(find_container)
    log_info "Found container: $CONTAINER"

    # Check if already authenticated
    if credentials_exist "$CONTAINER"; then
        log_warn "Credentials already exist. Re-authenticating will overwrite them."
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted."
            exit 0
        fi
    fi

    relax_firewall "$CONTAINER"

    log_info "Starting OAuth flow..."
    log_info "1. Copy the URL and open it in your browser"
    log_info "2. Authorize the application"
    log_info "3. Paste the authorization code when prompted"
    echo

    set +e
    docker exec -it "$CONTAINER" claude setup-token
    login_exit_code=$?
    set -e

    echo
    if [[ $login_exit_code -eq 0 ]]; then
        log_info "Authentication successful."

        if credentials_exist "$CONTAINER"; then
            log_info "Credentials verified."
        else
            log_warn "Could not verify credentials were saved."
        fi
    else
        log_error "OAuth failed with exit code: $login_exit_code"
        exit 1
    fi

    log_info "Done."
}

main "$@"
