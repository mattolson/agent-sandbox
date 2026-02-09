"""
Proxy policy enforcement addon for mitmproxy.

Logs HTTP/HTTPS traffic to stdout in JSON format.
In enforce mode, blocks requests to domains not on the allowlist.

Environment variables:
  PROXY_MODE: log (allow all) or enforce (block non-allowed)
  PROXY_LOG_LEVEL: quiet (errors only) or normal (default, one line per request)
"""

import json
import os
import sys
from datetime import datetime, timezone

import yaml
from mitmproxy import http

POLICY_PATH = "/etc/mitmproxy/policy.yaml"

SERVICE_DOMAINS = {
    "github": [
        "github.com",
        "*.github.com",
        "githubusercontent.com",
        "*.githubusercontent.com",
    ],
    "claude": [
        "*.anthropic.com",
        "*.claude.ai",
        "*.claude.com",
        "*.sentry.io",
        "*.datadoghq.com",
    ],
    "copilot": [
        "github.com",
        "api.github.com",
        "copilot-telemetry.githubusercontent.com",
        "collector.github.com",
        "default.exp-tas.com",
        "copilot-proxy.githubusercontent.com",
        "origin-tracker.githubusercontent.com",
        "*.githubcopilot.com",
        "*.individual.githubcopilot.com",
        "*.business.githubcopilot.com",
        "*.enterprise.githubcopilot.com",
        "*.githubassets.com",
    ],
    "vscode": [
        "update.code.visualstudio.com",
        "marketplace.visualstudio.com",
        "mobile.events.data.microsoft.com",
        "main.vscode-cdn.net",
        "*.vsassets.io",
    ],
    "jetbrains": [
       "plugins.jetbrains.com",
       "downloads.marketplace.jetbrains.com",
    ],
}


class PolicyEnforcer:
    def __init__(self):
        self.mode = os.getenv("PROXY_MODE", "log")
        self.log_level = os.getenv("PROXY_LOG_LEVEL", "normal")
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
            f"Policy loaded: {len(self.allowed_exact)} exact, "
            f"{len(self.allowed_wildcards)} wildcard"
        )

    def _add_domain(self, domain):
        self._log_info(f"Adding '{domain}' to allowlist")
        if domain.startswith("*."):
            self.allowed_wildcards.append(domain[2:])
        else:
            self.allowed_exact.add(domain)

    def _is_allowed(self, host):
        if self.mode == "log":
            return True
        if host in self.allowed_exact:
            return True
        for suffix in self.allowed_wildcards:
            if host == suffix or host.endswith("." + suffix):
                return True
        return False

    def _timestamp(self):
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    def _log_info(self, message):
        entry = {
            "ts": self._timestamp(),
            "type": "info",
            "msg": message,
        }
        print(json.dumps(entry), file=sys.stdout, flush=True)

    def _log(self, entry):
        if self.log_level != "quiet":
            print(json.dumps(entry), file=sys.stdout, flush=True)

    def http_connect(self, flow: http.HTTPFlow):
        """Handle HTTPS CONNECT - block disallowed hosts before tunnel established."""
        host = flow.request.host
        allowed = self._is_allowed(host)

        if not allowed:
            # Log and block immediately (no request/response will follow)
            self._log({
                "ts": self._timestamp(),
                "host": host,
                "action": "blocked",
            })
            flow.response = http.Response.make(
                403, f"Blocked by proxy policy: {host}"
            )

    def request(self, flow: http.HTTPFlow):
        """Handle HTTP requests - block disallowed hosts."""
        # HTTPS requests already filtered at http_connect
        if flow.request.scheme == "http":
            host = flow.request.host
            if not self._is_allowed(host):
                self._log({
                    "ts": self._timestamp(),
                    "method": flow.request.method,
                    "host": host,
                    "path": flow.request.path,
                    "action": "blocked",
                })
                flow.response = http.Response.make(
                    403, f"Blocked by proxy policy: {host}"
                )

    def response(self, flow: http.HTTPFlow):
        """Log completed requests with full details."""
        self._log({
            "ts": self._timestamp(),
            "method": flow.request.method,
            "host": flow.request.host,
            "path": flow.request.path,
            "status": flow.response.status_code,
            "action": "allowed",
        })

    def error(self, flow: http.HTTPFlow):
        """Log errors."""
        self._log({
            "ts": self._timestamp(),
            "host": flow.request.host if flow.request else "unknown",
            "path": flow.request.path if flow.request else "unknown",
            "error": str(flow.error) if flow.error else "unknown",
        })


addons = [PolicyEnforcer()]
