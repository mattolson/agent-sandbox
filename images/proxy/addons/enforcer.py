"""
Proxy policy enforcement addon for mitmproxy.

Logs HTTP/HTTPS traffic to stdout in JSON format.
In enforce mode, blocks requests to domains not on the allowlist.

The addon reads the rendered policy IR emitted by `render-policy`. In `m14.1`
that IR is canonicalized to a single top-level `domains` list where each entry
is a host record with a `host` field and normalized `rules`.

Reload behavior: the enforcer installs a `SIGHUP` handler on the mitmproxy
event loop that re-runs `render-policy` in-process and swaps the matcher
atomically. A failed reload keeps the previous matcher installed.

Environment variables:
  PROXY_MODE: log (allow all) or enforce (block non-allowed)
  PROXY_LOG_LEVEL: quiet (errors only) or normal (default, one line per request)
"""

from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import signal
import sys
from datetime import datetime, timezone
from importlib.machinery import SourceFileLoader
from pathlib import Path


ADDON_DIR = Path(__file__).resolve().parent
if str(ADDON_DIR) not in sys.path:
    sys.path.insert(0, str(ADDON_DIR))

from policy_matcher import (  # noqa: E402
    DEFAULT_POLICY_PATH,
    PolicyDecision,
    PolicyError,
    PolicyMatcher,
)

try:
    from mitmproxy import http
except ImportError:  # pragma: no cover - unit tests intentionally import without mitmproxy.
    http = None


FLOW_DECISION_METADATA_KEY = "agent_sandbox_policy_decision"

RELOAD_SIGNAL = signal.SIGHUP
RENDER_POLICY_PATH = Path("/usr/local/bin/render-policy")


def _load_render_policy_module(path):
    loader = SourceFileLoader("agent_sandbox_render_policy", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


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

    def event(self, entry, always=False):
        if self.log_level == "quiet" and not always:
            return
        self._emit(entry)

    def _emit(self, entry):
        print(json.dumps(entry), file=self.stream, flush=True)


class PolicyEnforcer:
    def __init__(
        self,
        mode=None,
        log_level=None,
        policy_path=None,
        matcher=None,
        logger=None,
        response_factory=None,
        reload_renderer=None,
    ):
        self.mode = mode or os.getenv("PROXY_MODE", "log")
        self.log_level = log_level or os.getenv("PROXY_LOG_LEVEL", "normal")
        self.logger = logger or JsonLogger(log_level=self.log_level)
        self.response_factory = response_factory
        self.reload_renderer = reload_renderer
        self.matcher = None
        self.domain_records = []
        self.exact_host_count = 0
        self.wildcard_host_count = 0
        self._reload_lock = asyncio.Lock()
        self._signal_loop = None

        if self.mode == "enforce":
            resolved_matcher = matcher
            if resolved_matcher is None:
                resolved_policy_path = policy_path or os.getenv(
                    "POLICY_PATH", DEFAULT_POLICY_PATH
                )
                try:
                    resolved_matcher = PolicyMatcher.from_policy_path(
                        resolved_policy_path
                    )
                except PolicyError as error:
                    self.logger.info(str(error))
                    sys.exit(1)

            self._set_matcher(resolved_matcher)
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

    def _set_matcher(self, matcher):
        self.matcher = matcher
        self.domain_records = [{"host": record.host} for record in matcher.host_records]
        self.exact_host_count = matcher.exact_host_count
        self.wildcard_host_count = matcher.wildcard_host_count

    def _log_loaded_policy(self):
        for domain in self.domain_records:
            self.logger.info(f"Adding '{domain['host']}' to allowlist")

        self.logger.info(
            f"Policy loaded from {self.matcher.source_description}: {len(self.domain_records)} host records, "
            f"{self.exact_host_count} exact, {self.wildcard_host_count} wildcard"
        )

    def running(self):
        if self.mode != "enforce":
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:  # pragma: no cover - only hit outside an asyncio context.
            return
        self._signal_loop = loop
        try:
            loop.add_signal_handler(RELOAD_SIGNAL, self._handle_reload_signal)
        except (NotImplementedError, RuntimeError) as error:
            self.logger.info(f"SIGHUP reload unavailable: {error}")
            self._signal_loop = None
            return
        self.logger.info("SIGHUP reload handler installed")

    def done(self):
        loop = self._signal_loop
        self._signal_loop = None
        if loop is None:
            return
        try:
            loop.remove_signal_handler(RELOAD_SIGNAL)
        except (NotImplementedError, RuntimeError, ValueError):  # pragma: no cover - best-effort cleanup.
            pass

    def _handle_reload_signal(self):
        asyncio.ensure_future(self.reload())

    async def reload(self):
        if self.mode != "enforce":
            return
        async with self._reload_lock:
            try:
                matcher = await asyncio.to_thread(self._render_matcher)
            except Exception as error:
                self.logger.event(
                    self._reload_event("rejected", error=str(error)),
                    always=True,
                )
                return
            self._set_matcher(matcher)
            self.logger.event(self._reload_event("applied"), always=True)

    def _render_matcher(self):
        if self.reload_renderer is not None:
            renderer = self.reload_renderer
        else:
            renderer = _load_render_policy_module(RENDER_POLICY_PATH).render_policy
        rendered_policy = renderer()
        return PolicyMatcher.from_policy_data(rendered_policy, path="reloaded policy")

    def _reload_event(self, action, error=None):
        entry = {
            "ts": self.logger.timestamp(),
            "type": "reload",
            "action": action,
        }
        if action == "applied":
            entry["host_records"] = len(self.domain_records)
            entry["exact_host_count"] = self.exact_host_count
            entry["wildcard_host_count"] = self.wildcard_host_count
        if error is not None:
            entry["error"] = error
        return entry

    def _make_response(self, status_code, body):
        factory = self.response_factory or self._default_response_factory()
        return factory(status_code, body)

    def _get_flow_metadata(self, flow):
        metadata = getattr(flow, "metadata", None)
        if metadata is None:
            metadata = {}
            flow.metadata = metadata
        return metadata

    def _store_decision(self, flow, decision):
        self._get_flow_metadata(flow)[FLOW_DECISION_METADATA_KEY] = decision.to_metadata()

    def _get_stored_decision(self, flow):
        metadata = self._get_flow_metadata(flow)
        payload = metadata.get(FLOW_DECISION_METADATA_KEY)
        if payload is None:
            return None
        return PolicyDecision.from_metadata(payload)

    def _clear_stored_decision(self, flow):
        self._get_flow_metadata(flow).pop(FLOW_DECISION_METADATA_KEY, None)

    def _decision_log_entry(self, decision):
        entry = {
            "ts": self.logger.timestamp(),
            "phase": decision.phase,
            "action": decision.action,
            "reason": decision.reason,
            "host": decision.host,
            "scheme": decision.scheme,
        }

        if decision.matched_host is not None:
            entry["matched_host"] = decision.matched_host
        if decision.method is not None:
            entry["method"] = decision.method
        if decision.path is not None:
            entry["path"] = decision.path

        return entry

    def http_connect(self, flow):
        """Handle HTTPS CONNECT - block disallowed hosts before tunnel established."""
        if self.mode != "enforce":
            return

        decision = self.matcher.evaluate_connect(flow.request.host)
        if decision.is_blocked():
            self.logger.event(self._decision_log_entry(decision))
            self._store_decision(flow, decision)
            flow.response = self._make_response(
                403,
                f"Blocked by proxy policy: {flow.request.host}",
            )
            return

        self._clear_stored_decision(flow)

    def request(self, flow):
        """Handle HTTP and decrypted HTTPS requests."""
        if self.mode != "enforce":
            return

        decision = self.matcher.evaluate_request(
            host=flow.request.host,
            scheme=flow.request.scheme,
            method=flow.request.method,
            request_target=flow.request.path,
        )

        if decision.is_blocked():
            self.logger.event(self._decision_log_entry(decision))
            self._store_decision(flow, decision)
            flow.response = self._make_response(
                403,
                f"Blocked by proxy policy: {flow.request.host}",
            )
            return

        self._store_decision(flow, decision)

    def response(self, flow):
        """Log completed requests with full details."""
        if self.mode != "enforce":
            self.logger.event({
                "ts": self.logger.timestamp(),
                "method": flow.request.method,
                "host": flow.request.host,
                "path": flow.request.path,
                "status": flow.response.status_code,
                "action": "allowed",
            })
            return

        decision = self._get_stored_decision(flow)
        if decision is None:
            self.logger.event({
                "ts": self.logger.timestamp(),
                "phase": "response",
                "action": "allowed",
                "reason": "untracked_response",
                "host": flow.request.host,
                "scheme": flow.request.scheme,
                "method": flow.request.method,
                "path": flow.request.path,
                "status": flow.response.status_code,
            })
            return

        if decision.is_blocked():
            return

        entry = self._decision_log_entry(decision)
        entry["status"] = flow.response.status_code
        self.logger.event(entry)

    def error(self, flow):
        """Log errors."""
        entry = {
            "ts": self.logger.timestamp(),
            "host": flow.request.host if flow.request else "unknown",
            "path": flow.request.path if flow.request else "unknown",
            "error": str(flow.error) if flow.error else "unknown",
        }

        if self.mode == "enforce":
            decision = self._get_stored_decision(flow)
            if decision is not None:
                entry["phase"] = decision.phase
                entry["reason"] = decision.reason
                if decision.matched_host is not None:
                    entry["matched_host"] = decision.matched_host

        self.logger.event(entry)


def build_addons():
    if http is None:
        return []
    return [PolicyEnforcer()]


addons = build_addons()
