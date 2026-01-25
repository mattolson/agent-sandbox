"""
Proxy policy enforcement addon for mitmproxy.

Logs all HTTP requests and HTTPS CONNECT tunnels to stdout in JSON format.
In enforce mode, blocks requests to domains not on the allowlist.

Modes (controlled by PROXY_MODE env var):
  - log: Log all traffic, allow everything (default)
  - enforce: Log all traffic, block non-allowed domains with 403
"""

import json
import os
import sys
from datetime import datetime, timezone

import yaml
from mitmproxy import http

POLICY_PATH = "/etc/mitmproxy/policy.yaml"

# Static service-to-domain mapping.
# Services in policy.yaml map to these domain patterns.
SERVICE_DOMAINS = {
    "github": [
        "github.com",
        "*.github.com",
        "githubusercontent.com",
        "*.githubusercontent.com",
    ],
}


class PolicyEnforcer:
    def __init__(self):
        self.mode = os.getenv("PROXY_MODE", "log")
        self.allowed_exact = set()
        self.allowed_wildcards = []

        if self.mode == "enforce":
            self._load_policy()
        elif self.mode == "log":
            self._log_info("Running in log mode (no enforcement)")
        else:
            self._log_info(f"Unknown PROXY_MODE '{self.mode}'. Use 'enforce' or 'log'.")
            sys.exit(1)

    def _load_policy(self):
        if not os.path.exists(POLICY_PATH):
            self._log_info(f"PROXY_MODE=enforce but no policy file at {POLICY_PATH}")
            sys.exit(1)

        with open(POLICY_PATH) as f:
            policy = yaml.safe_load(f) or {}

        for svc in policy.get("services") or []:
            patterns = SERVICE_DOMAINS.get(svc)
            if patterns:
                for domain in patterns:
                    self._add_domain(domain)
            else:
                self._log_info(f"Unknown service '{svc}' in policy, skipping")

        for domain in policy.get("domains") or []:
            self._add_domain(domain)

        self._log_info(
            f"Policy loaded: {len(self.allowed_exact)} exact domains, "
            f"{len(self.allowed_wildcards)} wildcard patterns"
        )

    def _add_domain(self, domain):
        if domain.startswith("*."):
            self.allowed_wildcards.append(domain[1:])
        else:
            self.allowed_exact.add(domain)

    def _is_allowed(self, host):
        if self.mode == "log":
            return True
        if host in self.allowed_exact:
            return True
        for suffix in self.allowed_wildcards:
            if host.endswith(suffix):
                return True
        return False

    def _log_info(self, message):
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "info",
            "message": message,
        }
        print(json.dumps(entry), file=sys.stdout, flush=True)

    def _log(self, entry):
        print(json.dumps(entry), file=sys.stdout, flush=True)

    def http_connect(self, flow: http.HTTPFlow):
        host = flow.request.host
        allowed = self._is_allowed(host)
        action = "allowed" if allowed else "blocked"

        self._log({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "connect",
            "host": host,
            "port": flow.request.port,
            "action": action,
        })

        if not allowed:
            flow.response = http.Response.make(
                403, f"Blocked by proxy policy: {host}"
            )

    def request(self, flow: http.HTTPFlow):
        if flow.request.scheme == "http":
            host = flow.request.host
            allowed = self._is_allowed(host)
            action = "allowed" if allowed else "blocked"

            self._log({
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "type": "http",
                "method": flow.request.method,
                "host": host,
                "port": flow.request.port,
                "path": flow.request.path,
                "action": action,
            })

            if not allowed:
                flow.response = http.Response.make(
                    403, f"Blocked by proxy policy: {host}"
                )

    def error(self, flow: http.HTTPFlow):
        self._log({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "type": "error",
            "host": flow.request.host,
            "port": flow.request.port,
            "error": str(flow.error) if flow.error else "unknown",
        })


addons = [PolicyEnforcer()]
