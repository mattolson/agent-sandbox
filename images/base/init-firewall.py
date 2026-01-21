#!/usr/bin/env python3
"""
Agent Sandbox Firewall Initialization

Reads policy.json and configures iptables/ipset rules to allow only
whitelisted outbound connections.
"""

import json
import os
import re
import socket
import subprocess
import sys
import urllib.request
from ipaddress import ip_address, ip_network, collapse_addresses
from typing import List, Optional, Set


# Constants
DEFAULT_POLICY_FILE = "/etc/agent-sandbox/policy.json"
IPSET_NAME = "allowed-domains"
GITHUB_META_URL = "https://api.github.com/meta"
VERIFY_BLOCKED_URL = "https://example.com"
VERIFY_GITHUB_URL = "https://api.github.com/zen"


class FirewallError(Exception):
    """Custom exception for firewall configuration errors."""
    pass


def run_cmd(args: List[str], check: bool = True, capture: bool = False) -> Optional[str]:
    """Execute a command with error handling."""
    result = subprocess.run(args, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise FirewallError(f"Command failed: {' '.join(args)}\n{result.stderr}")
    return result.stdout if capture else None


def run_cmd_unchecked(args: List[str]) -> subprocess.CompletedProcess:
    """Execute a command without raising on failure."""
    return subprocess.run(args, capture_output=True, text=True)


def validate_ipv4(ip: str) -> bool:
    """Validate an IPv4 address."""
    try:
        addr = ip_address(ip)
        return addr.version == 4
    except ValueError:
        return False


def validate_cidr(cidr: str) -> bool:
    """Validate a CIDR range (IPv4 only)."""
    try:
        network = ip_network(cidr, strict=False)
        return network.version == 4
    except ValueError:
        return False


def load_policy(path: str) -> dict:
    """Load and validate policy JSON file."""
    if not os.path.isfile(path):
        raise FirewallError(f"Policy file not found: {path}")

    print(f"Using policy file: {path}")

    with open(path, "r") as f:
        try:
            policy = json.load(f)
        except json.JSONDecodeError as e:
            raise FirewallError(f"Invalid JSON in policy file: {e}")

    if not isinstance(policy, dict):
        raise FirewallError("Policy must be a JSON object")

    services = policy.get("services", [])
    if not isinstance(services, list):
        raise FirewallError("'services' must be an array")

    domains = policy.get("domains", [])
    if not isinstance(domains, list):
        raise FirewallError("'domains' must be an array")

    return policy


def save_docker_dns_rules() -> str:
    """Extract Docker DNS NAT rules before flushing."""
    result = run_cmd_unchecked(["iptables-save", "-t", "nat"])
    if result.returncode == 0 and result.stdout:
        lines = [line for line in result.stdout.split("\n") if "127.0.0.11" in line]
        return "\n".join(lines)
    return ""


def flush_rules() -> None:
    """Flush all iptables rules and destroy ipset."""
    # Flush iptables
    run_cmd(["iptables", "-F"])
    run_cmd(["iptables", "-X"])
    run_cmd(["iptables", "-t", "nat", "-F"])
    run_cmd(["iptables", "-t", "nat", "-X"])
    run_cmd(["iptables", "-t", "mangle", "-F"])
    run_cmd(["iptables", "-t", "mangle", "-X"])

    # Destroy ipset (ignore if doesn't exist)
    run_cmd_unchecked(["ipset", "destroy", IPSET_NAME])


def restore_docker_dns(rules: str) -> None:
    """Restore Docker DNS NAT rules."""
    if not rules:
        print("No Docker DNS rules to restore")
        return

    print("Restoring Docker DNS rules...")

    # Create chains if they don't exist
    run_cmd_unchecked(["iptables", "-t", "nat", "-N", "DOCKER_OUTPUT"])
    run_cmd_unchecked(["iptables", "-t", "nat", "-N", "DOCKER_POSTROUTING"])

    # Restore each rule
    for rule in rules.strip().split("\n"):
        if rule:
            # Rules look like: -A DOCKER_OUTPUT -d 127.0.0.11/32 ...
            parts = rule.split()
            run_cmd_unchecked(["iptables", "-t", "nat"] + parts)


def setup_foundation_rules() -> None:
    """Set up DNS, SSH, and localhost rules."""
    # Allow outbound DNS
    run_cmd(["iptables", "-A", "OUTPUT", "-p", "udp", "--dport", "53", "-j", "ACCEPT"])
    # Allow inbound DNS responses
    run_cmd(["iptables", "-A", "INPUT", "-p", "udp", "--sport", "53", "-j", "ACCEPT"])
    # Allow outbound SSH
    run_cmd(["iptables", "-A", "OUTPUT", "-p", "tcp", "--dport", "22", "-j", "ACCEPT"])
    # Allow inbound SSH responses
    run_cmd(["iptables", "-A", "INPUT", "-p", "tcp", "--sport", "22", "-m", "state", "--state", "ESTABLISHED", "-j", "ACCEPT"])
    # Allow localhost
    run_cmd(["iptables", "-A", "INPUT", "-i", "lo", "-j", "ACCEPT"])
    run_cmd(["iptables", "-A", "OUTPUT", "-o", "lo", "-j", "ACCEPT"])


def create_ipset() -> None:
    """Create ipset for allowed domains."""
    run_cmd(["ipset", "create", IPSET_NAME, "hash:net"])


def fetch_github_ips() -> List[str]:
    """Fetch GitHub IP ranges from api.github.com/meta."""
    print("Fetching GitHub IP ranges...")

    try:
        req = urllib.request.Request(
            GITHUB_META_URL,
            headers={"User-Agent": "agent-sandbox-firewall/1.0"}
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode())
    except Exception as e:
        raise FirewallError(f"Failed to fetch GitHub IP ranges: {e}")

    # Validate response has required fields
    required_keys = ["web", "api", "git"]
    for key in required_keys:
        if key not in data:
            raise FirewallError(f"GitHub API response missing '{key}' field")

    # Collect IPv4 CIDRs
    cidrs: Set[str] = set()
    for key in required_keys:
        for cidr in data[key]:
            # Skip IPv6
            if ":" in cidr:
                continue
            if not validate_cidr(cidr):
                raise FirewallError(f"Invalid CIDR from GitHub meta: {cidr}")
            cidrs.add(cidr)

    # Aggregate overlapping CIDRs
    networks = [ip_network(cidr, strict=False) for cidr in cidrs]
    aggregated = list(collapse_addresses(networks))

    return [str(n) for n in aggregated]


def resolve_domain(domain: str) -> List[str]:
    """Resolve domain to IPv4 addresses via DNS."""
    print(f"Resolving {domain}...")

    try:
        results = socket.getaddrinfo(domain, None, socket.AF_INET)
        ips = list(set(r[4][0] for r in results))

        if not ips:
            raise FirewallError(f"No IPv4 addresses found for {domain}")

        for ip in ips:
            if not validate_ipv4(ip):
                raise FirewallError(f"Invalid IP from DNS for {domain}: {ip}")

        return ips
    except socket.gaierror as e:
        raise FirewallError(f"Failed to resolve {domain}: {e}")


def add_to_ipset(ip_or_cidr: str) -> None:
    """Add IP or CIDR to the allowed-domains ipset."""
    run_cmd(["ipset", "add", IPSET_NAME, ip_or_cidr])


def process_services(services: List[str]) -> None:
    """Process services from policy (currently only 'github')."""
    print("Processing services...")

    for service in services:
        if service == "github":
            cidrs = fetch_github_ips()
            print("Processing GitHub IPs...")
            for cidr in cidrs:
                print(f"  Adding GitHub range {cidr}")
                add_to_ipset(cidr)
        else:
            print(f"WARNING: Unknown service '{service}', skipping")


def process_domains(domains: List[str]) -> None:
    """Process domains from policy, resolving each via DNS."""
    print("Processing domains...")

    for domain in domains:
        ips = resolve_domain(domain)
        for ip in ips:
            print(f"  Adding {ip} for {domain}")
            add_to_ipset(ip)


def setup_host_network() -> None:
    """Allow traffic to host network (detected from default route)."""
    result = run_cmd(["ip", "route"], capture=True)

    host_ip = None
    for line in result.split("\n"):
        if line.startswith("default"):
            parts = line.split()
            if len(parts) >= 3:
                host_ip = parts[2]
                break

    if not host_ip:
        raise FirewallError("Failed to detect host IP")

    # Convert to /24 network
    match = re.match(r"^(\d+\.\d+\.\d+)\.\d+$", host_ip)
    if not match:
        raise FirewallError(f"Invalid host IP format: {host_ip}")

    host_network = f"{match.group(1)}.0/24"
    print(f"Host network detected as: {host_network}")

    run_cmd(["iptables", "-A", "INPUT", "-s", host_network, "-j", "ACCEPT"])
    run_cmd(["iptables", "-A", "OUTPUT", "-d", host_network, "-j", "ACCEPT"])


def apply_firewall_rules() -> None:
    """Apply final iptables rules (default DROP, allow ipset)."""
    # Set default policies to DROP
    run_cmd(["iptables", "-P", "INPUT", "DROP"])
    run_cmd(["iptables", "-P", "FORWARD", "DROP"])
    run_cmd(["iptables", "-P", "OUTPUT", "DROP"])

    # Allow established connections
    run_cmd(["iptables", "-A", "INPUT", "-m", "state", "--state", "ESTABLISHED,RELATED", "-j", "ACCEPT"])
    run_cmd(["iptables", "-A", "OUTPUT", "-m", "state", "--state", "ESTABLISHED,RELATED", "-j", "ACCEPT"])

    # Allow traffic to allowed domains ipset
    run_cmd(["iptables", "-A", "OUTPUT", "-m", "set", "--match-set", IPSET_NAME, "dst", "-j", "ACCEPT"])

    # Reject all other outbound traffic
    run_cmd(["iptables", "-A", "OUTPUT", "-j", "REJECT", "--reject-with", "icmp-admin-prohibited"])

    print("Firewall configuration complete")


def verify_firewall(policy: dict) -> None:
    """Verify firewall blocks example.com and allows configured endpoints."""
    print("Verifying firewall rules...")

    # Test blocked destination
    result = run_cmd_unchecked(["curl", "--connect-timeout", "5", VERIFY_BLOCKED_URL])
    if result.returncode == 0:
        raise FirewallError(f"Firewall verification failed - was able to reach {VERIFY_BLOCKED_URL}")
    print("Firewall verification passed - unable to reach https://example.com as expected")

    # Determine verification endpoint
    verify_url = None
    verify_name = None

    services = policy.get("services", [])
    if "github" in services:
        verify_url = VERIFY_GITHUB_URL
        verify_name = "api.github.com"
    else:
        domains = policy.get("domains", [])
        if domains:
            verify_url = f"https://{domains[0]}"
            verify_name = domains[0]

    # Test allowed destination
    if verify_url:
        result = run_cmd_unchecked(["curl", "--connect-timeout", "5", "-m", "10", verify_url])
        if result.returncode != 0:
            raise FirewallError(f"Firewall verification failed - unable to reach {verify_name}")
        print(f"Firewall verification passed - able to reach {verify_name}")
    else:
        print("WARNING: No services or domains in policy to verify positive connectivity")


def main() -> int:
    """Main entry point."""
    policy_file = os.environ.get("POLICY_FILE", DEFAULT_POLICY_FILE)

    try:
        policy = load_policy(policy_file)
        docker_dns = save_docker_dns_rules()
        flush_rules()
        restore_docker_dns(docker_dns)
        setup_foundation_rules()
        create_ipset()
        process_services(policy.get("services", []))
        process_domains(policy.get("domains", []))
        setup_host_network()
        apply_firewall_rules()
        verify_firewall(policy)
        print("Firewall initialization complete")
        return 0
    except FirewallError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"FATAL: Unexpected error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
