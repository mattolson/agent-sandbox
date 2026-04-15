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

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

import yaml

try:
    from mitmproxy import http
except ImportError:  # pragma: no cover - unit tests intentionally import without mitmproxy.
    http = None


DEFAULT_POLICY_PATH = "/etc/mitmproxy/policy.yaml"


class PolicyError(Exception):
    """Raised when rendered proxy policy cannot be loaded safely."""


class JsonLogger:
    def __init__(self, log_level="normal", stream=None, clock=None):
        self.log_level = log_level
        self.stream = stream if stream is not None else sys.stdout
        self.clock = clock or (lambda: datetime.now(timezone.utc))

    def timestamp(self):
        return self.clock().strftime("%Y-%m-%d %H:%M:%S")

    def info(self, message):
        self._emit({
            "ts": self.timestamp(),
            "type": "info",
            "msg": message,
        })

    def event(self, entry):
        if self.log_level == "quiet":
            return
        self._emit(entry)

    def _emit(self, entry):
        print(json.dumps(entry), file=self.stream, flush=True)


class HostAllowlist:
    def __init__(self, domain_records, source_description="rendered policy"):
        self.domain_records = list(domain_records)
        self.source_description = source_description
        self.allowed_exact = set()
        self.allowed_wildcards = []

        for record in self.domain_records:
            host = record["host"].lower()
            if host.startswith("*."):
                self.allowed_wildcards.append(host[2:])
            else:
                self.allowed_exact.add(host)

    @classmethod
    def from_policy_path(cls, path):
        if not os.path.exists(path):
            raise PolicyError(f"PROXY_MODE=enforce but no policy file at {path}")

        with open(path, encoding="utf-8") as handle:
            policy = yaml.safe_load(handle) or {}

        return cls.from_policy_data(policy, path=path)

    @classmethod
    def from_policy_data(cls, policy, path=None):
        policy_context = f"Policy at {path}" if path else "Policy"
        if not isinstance(policy, dict):
            raise PolicyError(f"{policy_context} must be a YAML mapping")

        domains = policy.get("domains") or []
        if not isinstance(domains, list):
            raise PolicyError(
                f"{policy_context} field 'domains' must be a YAML list"
            )

        source_description = path or "rendered policy"
        return cls(
            cls._load_domain_records(domains),
            source_description=source_description,
        )

    @staticmethod
    def _load_domain_records(domains):
        records = []

        for index, domain in enumerate(domains):
            if isinstance(domain, str):
                records.append({"host": domain})
                continue

            if not isinstance(domain, dict):
                raise PolicyError(
                    f"Policy domains[{index}] must be a string or mapping, "
                    f"got {type(domain).__name__}: {domain!r}"
                )

            host = domain.get("host")
            if not isinstance(host, str) or not host:
                raise PolicyError(
                    f"Policy domains[{index}].host must be a non-empty string, got {host!r}"
                )

            records.append(dict(domain))

        indexed_records = list(enumerate(records))
        sorted_records = sorted(
            indexed_records,
            key=lambda item: HostAllowlist._host_sort_key(item[1]["host"], item[0]),
        )
        return [record for _, record in sorted_records]

    @staticmethod
    def _host_sort_key(host, original_index):
        if host.startswith("*."):
            return (1, -len(host[2:]), original_index)
        return (0, 0, original_index)

    def is_allowed(self, host):
        normalized_host = host.lower()
        if normalized_host in self.allowed_exact:
            return True

        for suffix in self.allowed_wildcards:
            if normalized_host == suffix or normalized_host.endswith("." + suffix):
                return True

        return False


class PolicyEnforcer:
    def __init__(
        self,
        mode=None,
        log_level=None,
        policy_path=None,
        allowlist=None,
        logger=None,
        response_factory=None,
    ):
        self.mode = mode or os.getenv("PROXY_MODE", "log")
        self.log_level = log_level or os.getenv("PROXY_LOG_LEVEL", "normal")
        self.logger = logger or JsonLogger(log_level=self.log_level)
        self.response_factory = response_factory
        self.allowlist = None
        self.allowed_exact = set()
        self.allowed_wildcards = []
        self.domain_records = []

        if self.mode == "enforce":
            resolved_allowlist = allowlist
            if resolved_allowlist is None:
                resolved_policy_path = policy_path or os.getenv(
                    "POLICY_PATH", DEFAULT_POLICY_PATH
                )
                try:
                    resolved_allowlist = HostAllowlist.from_policy_path(
                        resolved_policy_path
                    )
                except PolicyError as error:
                    self.logger.info(str(error))
                    sys.exit(1)

            self._set_allowlist(resolved_allowlist)
            self._log_loaded_policy()
        elif self.mode == "log":
            self.logger.info("Running in log mode (no enforcement)")
        else:
            self.logger.info(
                f"Unknown PROXY_MODE '{self.mode}'. Use 'enforce' or 'log'."
            )
            sys.exit(1)

    def _default_response_factory(self):
        if http is None:
            raise RuntimeError(
                "mitmproxy is not available; pass response_factory when testing PolicyEnforcer"
            )
        return http.Response.make

    def _set_allowlist(self, allowlist):
        self.allowlist = allowlist
        self.domain_records = list(allowlist.domain_records)
        self.allowed_exact = set(allowlist.allowed_exact)
        self.allowed_wildcards = list(allowlist.allowed_wildcards)

    def _log_loaded_policy(self):
        for domain in self.domain_records:
            self.logger.info(f"Adding '{domain['host']}' to allowlist")

        self.logger.info(
            f"Policy loaded from {self.allowlist.source_description}: {len(self.domain_records)} host records, "
            f"{len(self.allowed_exact)} exact, {len(self.allowed_wildcards)} wildcard"
        )

    def _make_response(self, status_code, body):
        factory = self.response_factory or self._default_response_factory()
        return factory(status_code, body)

    def _is_allowed(self, host):
        if self.mode == "log":
            return True
        return self.allowlist.is_allowed(host)

    def http_connect(self, flow):
        """Handle HTTPS CONNECT - block disallowed hosts before tunnel established."""
        host = flow.request.host
        if self._is_allowed(host):
            return

        self.logger.event({
            "ts": self.logger.timestamp(),
            "host": host,
            "action": "blocked",
        })
        flow.response = self._make_response(403, f"Blocked by proxy policy: {host}")

    def request(self, flow):
        """Handle HTTP requests - block disallowed hosts."""
        if flow.request.scheme != "http":
            return

        host = flow.request.host
        if self._is_allowed(host):
            return

        self.logger.event({
            "ts": self.logger.timestamp(),
            "method": flow.request.method,
            "host": host,
            "path": flow.request.path,
            "action": "blocked",
        })
        flow.response = self._make_response(403, f"Blocked by proxy policy: {host}")

    def response(self, flow):
        """Log completed requests with full details."""
        self.logger.event({
            "ts": self.logger.timestamp(),
            "method": flow.request.method,
            "host": flow.request.host,
            "path": flow.request.path,
            "status": flow.response.status_code,
            "action": "allowed",
        })

    def error(self, flow):
        """Log errors."""
        self.logger.event({
            "ts": self.logger.timestamp(),
            "host": flow.request.host if flow.request else "unknown",
            "path": flow.request.path if flow.request else "unknown",
            "error": str(flow.error) if flow.error else "unknown",
        })


def build_addons():
    if http is None:
        return []
    return [PolicyEnforcer()]


addons = build_addons()
