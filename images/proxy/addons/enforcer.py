"""
Proxy policy enforcement addon for mitmproxy.

Logs HTTP/HTTPS traffic to stdout in JSON format.
In enforce mode, blocks requests to domains not on the allowlist.

The addon reads the rendered policy IR emitted by `render-policy`. In `m14.1`
that IR is canonicalized to a single top-level `domains` list where each entry
is a host record with a `host` field and normalized `rules`.

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


class PolicyEnforcer:
    def __init__(self):
        self.mode = os.getenv("PROXY_MODE", "log")
        self.log_level = os.getenv("PROXY_LOG_LEVEL", "normal")
        self.allowed_exact = set()
        self.allowed_wildcards = []
        self.domain_records = []

        if self.mode == "enforce":
            self._load_policy()
        elif self.mode == "log":
            self._log_info("Running in log mode (no enforcement)")
        else:
            self._log_info(f"Unknown PROXY_MODE '{self.mode}'. Use 'enforce' or 'log'.")
            sys.exit(1)

    def _load_policy(self):
        policy_path = os.getenv("POLICY_PATH", "/etc/mitmproxy/policy.yaml")

        if not os.path.exists(policy_path):
            self._log_info(f"PROXY_MODE=enforce but no policy file at {policy_path}")
            sys.exit(1)

        with open(policy_path) as f:
            policy = yaml.safe_load(f) or {}

        if not isinstance(policy, dict):
            self._log_info(f"Policy at {policy_path} must be a YAML mapping")
            sys.exit(1)

        self.domain_records = self._load_domain_records(policy.get("domains") or [])

        for domain in self.domain_records:
            self._add_domain(domain["host"])

        self._log_info(
            f"Policy loaded from {policy_path}: {len(self.domain_records)} host records, "
            f"{len(self.allowed_exact)} exact, {len(self.allowed_wildcards)} wildcard"
        )

    def _add_domain(self, domain):
        domain = domain.lower()
        self._log_info(f"Adding '{domain}' to allowlist")
        if domain.startswith("*."):
            self.allowed_wildcards.append(domain[2:])
        else:
            self.allowed_exact.add(domain)

    def _load_domain_records(self, domains):
        records = []

        for index, domain in enumerate(domains):
            if isinstance(domain, str):
                records.append({"host": domain})
                continue

            if not isinstance(domain, dict):
                self._log_info(
                    f"Policy domains[{index}] must be a string or mapping, "
                    f"got {type(domain).__name__}: {domain!r}"
                )
                sys.exit(1)

            host = domain.get("host")
            if not isinstance(host, str) or not host:
                self._log_info(
                    f"Policy domains[{index}].host must be a non-empty string, got {host!r}"
                )
                sys.exit(1)

            records.append(domain)

        indexed_records = list(enumerate(records))
        sorted_records = sorted(
            indexed_records,
            key=lambda item: self._host_sort_key(item[1]["host"], item[0]),
        )
        return [record for _, record in sorted_records]

    def _host_sort_key(self, host, original_index):
        if host.startswith("*."):
            return (1, -len(host[2:]), original_index)
        return (0, 0, original_index)

    def _is_allowed(self, host):
        if self.mode == "log":
            return True
        host = host.lower()
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
