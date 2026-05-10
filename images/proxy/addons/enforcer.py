"""
Proxy policy enforcement addon for mitmproxy.

Logs HTTP/HTTPS traffic to stdout in JSON format.
In enforce mode, blocks requests to domains not on the allowlist.

The addon reads the rendered policy IR emitted by `render-policy`. That IR is
canonicalized to a single top-level `domains` list where each entry is a host
record with a `host` field and normalized `rules`.

Reload behavior: the enforcer installs a `SIGHUP` handler on the mitmproxy
event loop that re-runs `render-policy` in-process and swaps the matcher
atomically. A failed reload keeps the previous matcher installed.

Environment variables:
  PROXY_MODE: log (allow all) or enforce (block non-allowed)
  PROXY_LOG_LEVEL: quiet (errors only) or normal (default, one line per request)
  AGENTBOX_RENDER_POLICY_PATH: optional override for the render-policy binary
    path. Defaults to /usr/local/bin/render-policy (the location the proxy
    image installs it to).
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

PROXY_DIR = ADDON_DIR.parent
PROXY_LIB_DIR = Path(
    os.getenv("AGENTBOX_PROXY_LIB_DIR", "/usr/local/lib/agent-sandbox/proxy")
)
for module_path in reversed((PROXY_DIR, PROXY_LIB_DIR)):
    module_path_text = str(module_path)
    if module_path_text not in sys.path:
        sys.path.insert(0, module_path_text)

from policy_matcher import (  # noqa: E402
    DEFAULT_POLICY_PATH,
    PolicyDecision,
    PolicyError,
    PolicyMatcher,
)
from secret_resolver import (  # noqa: E402
    SecretResolver,
    SecretResolverError,
    render_header_value,
)

try:
    from mitmproxy import http
except ImportError:  # pragma: no cover - unit tests intentionally import without mitmproxy.
    http = None


FLOW_DECISION_METADATA_KEY = "agent_sandbox_policy_decision"

RELOAD_SIGNAL = signal.SIGHUP
RENDER_POLICY_PATH = Path(
    os.getenv("AGENTBOX_RENDER_POLICY_PATH", "/usr/local/bin/render-policy")
)


def _load_render_policy_module(path):
    original_sys_path = list(sys.path)
    loader = SourceFileLoader("agent_sandbox_render_policy", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(module)
    finally:
        sys.path[:] = original_sys_path
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
        secret_resolver=None,
        secret_resolver_factory=None,
    ):
        self.mode = mode or os.getenv("PROXY_MODE", "log")
        self.log_level = log_level or os.getenv("PROXY_LOG_LEVEL", "normal")
        self.logger = logger or JsonLogger(log_level=self.log_level)
        self.response_factory = response_factory
        self.reload_renderer = reload_renderer
        self._secret_resolver = secret_resolver
        self._secret_resolver_factory = secret_resolver_factory or SecretResolver.from_env
        self.matcher = None
        self.domain_records = []
        self.exact_host_count = 0
        self.wildcard_host_count = 0
        self._reload_lock = asyncio.Lock()
        self._reload_tasks: set[asyncio.Task] = set()
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
        task = asyncio.create_task(self.reload())
        self._reload_tasks.add(task)
        task.add_done_callback(self._reload_tasks.discard)

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
            self.logger.event(
                self._reload_event("applied"),
                always=True,
            )

    def _render_matcher(self):
        module = None
        if self.reload_renderer is not None:
            rendered_policy = self.reload_renderer()
        else:
            module = _load_render_policy_module(RENDER_POLICY_PATH)
            rendered_policy = module.render_policy()
        matcher = PolicyMatcher.from_policy_data(rendered_policy, path="reloaded policy")
        if module is not None and hasattr(module, "write_credential_shim_init"):
            module.write_credential_shim_init(rendered_policy)
        return matcher

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

    def _set_block_response(self, flow):
        if getattr(flow.request, "stream", False):
            flow.request.stream = False
        flow.response = self._make_response(
            403,
            f"Blocked by proxy policy: {flow.request.host}",
        )

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
        if decision.matched_rule_index is not None:
            entry["matched_rule_index"] = decision.matched_rule_index
        if decision.detail is not None:
            entry["detail"] = decision.detail
        if decision.header is not None:
            entry["header"] = decision.header
        if decision.secret is not None:
            entry["secret"] = decision.secret
        if decision.error is not None:
            entry["error"] = decision.error

        return entry

    def _get_secret_resolver(self):
        if self._secret_resolver is None:
            self._secret_resolver = self._secret_resolver_factory()
        return self._secret_resolver

    def _header_transform_config(self, header):
        transform = {"type": header.transform_type}
        if header.transform_type == "basic":
            transform["username"] = header.username
        return transform

    def _find_existing_header_name(self, headers, target_name):
        target = target_name.lower()
        try:
            keys = headers.keys()
        except AttributeError:
            keys = []
        for existing_name in keys:
            if str(existing_name).lower() == target:
                return existing_name

        try:
            if target_name in headers:
                return target_name
        except TypeError:
            pass
        return None

    def _set_request_header(self, headers, name, value, existing_name=None):
        if existing_name is not None and str(existing_name).lower() == name.lower():
            try:
                del headers[existing_name]
            except KeyError:
                pass
        headers[name] = value

    def _injection_failure_decision(
        self,
        decision,
        detail,
        header=None,
        secret=None,
        error=None,
    ):
        return PolicyDecision(
            phase="request",
            action="blocked",
            reason="header_injection_failed",
            host=decision.host,
            scheme=decision.scheme,
            matched_host=decision.matched_host,
            method=decision.method,
            path=decision.path,
            matched_rule_index=decision.matched_rule_index,
            detail=detail,
            header=header,
            secret=secret,
            error=error,
        )

    def _header_injection_event(self, decision, headers, warnings):
        entry = {
            "ts": self.logger.timestamp(),
            "type": "header_injection",
            "action": "applied",
            "host": decision.host,
            "scheme": decision.scheme,
            "headers": headers,
        }
        if decision.matched_host is not None:
            entry["matched_host"] = decision.matched_host
        if decision.method is not None:
            entry["method"] = decision.method
        if decision.path is not None:
            entry["path"] = decision.path
        if decision.matched_rule_index is not None:
            entry["matched_rule_index"] = decision.matched_rule_index
        if warnings:
            entry["warnings"] = warnings
        return entry

    def _apply_request_transform(self, flow, decision):
        rule_transform = decision.rule_transform
        request_transform = (
            rule_transform.request if rule_transform is not None else None
        )
        if request_transform is None:
            return None

        headers = getattr(flow.request, "headers", None)
        if headers is None:
            headers = {}
            flow.request.headers = headers

        existing_headers = []
        for header in request_transform.headers:
            existing_name = self._find_existing_header_name(headers, header.name)
            if (
                existing_name is not None
                and request_transform.on_existing_header == "fail"
            ):
                return self._injection_failure_decision(
                    decision,
                    detail="existing_header_present",
                    header=header.name,
                    secret=header.secret,
                )
            existing_headers.append(existing_name)

        try:
            resolver = self._get_secret_resolver()
        except SecretResolverError as error:
            first_header = request_transform.headers[0]
            return self._injection_failure_decision(
                decision,
                detail="secret_resolver_unavailable",
                header=first_header.name,
                secret=first_header.secret,
                error=str(error),
            )

        staged_headers = []
        injected = []
        warnings = []
        for header, existing_name in zip(request_transform.headers, existing_headers):
            try:
                resolution = resolver.resolve(header.secret)
            except SecretResolverError as error:
                return self._injection_failure_decision(
                    decision,
                    detail="secret_resolution_failed",
                    header=header.name,
                    secret=header.secret,
                    error=str(error),
                )

            try:
                rendered_value = render_header_value(
                    resolution.value,
                    self._header_transform_config(header),
                )
            except SecretResolverError as error:
                return self._injection_failure_decision(
                    decision,
                    detail="transform_failed",
                    header=header.name,
                    secret=header.secret,
                    error=str(error),
                )

            staged_headers.append((header.name, rendered_value, existing_name))
            injected.append({
                "name": header.name,
                "secret": header.secret,
                "transform": header.transform_type,
            })
            for warning in resolution.warnings:
                warnings.append({
                    "code": warning.code,
                    "path": warning.path,
                    "secret": header.secret,
                })

        for name, rendered_value, existing_name in staged_headers:
            self._set_request_header(headers, name, rendered_value, existing_name)

        self.logger.event(self._header_injection_event(decision, injected, warnings))
        return None

    def http_connect(self, flow):
        """Handle HTTPS CONNECT - block disallowed hosts before tunnel established."""
        if self.mode != "enforce":
            return

        decision = self.matcher.evaluate_connect(flow.request.host)
        if decision.is_blocked():
            self.logger.event(self._decision_log_entry(decision))
            self._store_decision(flow, decision)
            self._set_block_response(flow)
            return

        self._clear_stored_decision(flow)

    def _handle_request_decision(self, flow):
        if self.mode != "enforce":
            return

        existing_decision = self._get_stored_decision(flow)
        if existing_decision is not None:
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
            self._set_block_response(flow)
            return

        injection_failure = self._apply_request_transform(flow, decision)
        if injection_failure is not None:
            self.logger.event(self._decision_log_entry(injection_failure))
            self._store_decision(flow, injection_failure)
            self._set_block_response(flow)
            return

        self._store_decision(flow, decision)

    def requestheaders(self, flow):
        """Handle HTTP and decrypted HTTPS requests before any body streams upstream."""
        self._handle_request_decision(flow)

    def request(self, flow):
        """Handle HTTP and decrypted HTTPS requests."""
        self._handle_request_decision(flow)

    def responseheaders(self, flow):
        """Stream response bodies without enabling mitmproxy request-body streaming."""
        if flow.response is not None:
            flow.response.stream = True

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
