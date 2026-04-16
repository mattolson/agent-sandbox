from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import parse_qs, urlsplit

import yaml


DEFAULT_POLICY_PATH = "/etc/mitmproxy/policy.yaml"
DEFAULT_RULE_SCHEMES = ("http", "https")


class PolicyError(Exception):
    """Raised when rendered proxy policy cannot be loaded safely."""


@dataclass(frozen=True)
class PolicyDecision:
    phase: str
    action: str
    reason: str
    host: str
    scheme: str
    matched_host: str | None = None
    method: str | None = None
    path: str | None = None

    def is_blocked(self):
        return self.action == "blocked"

    def to_metadata(self):
        return {
            "phase": self.phase,
            "action": self.action,
            "reason": self.reason,
            "host": self.host,
            "scheme": self.scheme,
            "matched_host": self.matched_host,
            "method": self.method,
            "path": self.path,
        }

    @classmethod
    def from_metadata(cls, data):
        return cls(
            phase=data["phase"],
            action=data["action"],
            reason=data["reason"],
            host=data["host"],
            scheme=data["scheme"],
            matched_host=data.get("matched_host"),
            method=data.get("method"),
            path=data.get("path"),
        )


@dataclass(frozen=True)
class RuntimeRule:
    schemes: tuple[str, ...]
    methods: tuple[str, ...] | None = None
    path_exact: str | None = None
    path_prefix: str | None = None
    query_exact: tuple[tuple[str, tuple[str, ...]], ...] | None = None

    def matches_scheme(self, scheme):
        return scheme.lower() in self.schemes

    def needs_request_inspection(self):
        return (
            self.methods is not None
            or self.path_exact is not None
            or self.path_prefix is not None
            or self.query_exact is not None
        )

    def allows_connect_fast_path(self, scheme):
        return self.matches_scheme(scheme) and not self.needs_request_inspection()

    def matches_request(self, scheme, method, path, normalized_query):
        if not self.matches_scheme(scheme):
            return False

        if self.methods is not None and method.upper() not in self.methods:
            return False

        if self.path_exact is not None and path != self.path_exact:
            return False

        if self.path_prefix is not None and not path.startswith(self.path_prefix):
            return False

        if self.query_exact is not None and normalized_query != self.query_exact:
            return False

        return True


@dataclass(frozen=True)
class HostRecord:
    host: str
    wildcard_suffix: str | None
    rules: tuple[RuntimeRule, ...]

    def matches_host(self, host):
        normalized_host = host.lower()
        if self.wildcard_suffix is None:
            return normalized_host == self.host
        return (
            normalized_host == self.wildcard_suffix
            or normalized_host.endswith("." + self.wildcard_suffix)
        )

    def can_match_scheme(self, scheme):
        return any(rule.matches_scheme(scheme) for rule in self.rules)

    def allows_connect_fast_path(self, scheme):
        return any(rule.allows_connect_fast_path(scheme) for rule in self.rules)


class PolicyMatcher:
    def __init__(self, host_records, source_description="rendered policy"):
        self.host_records = tuple(host_records)
        self.source_description = source_description
        self.exact_host_count = sum(
            1 for record in self.host_records if record.wildcard_suffix is None
        )
        self.wildcard_host_count = len(self.host_records) - self.exact_host_count

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
            cls._compile_host_records(domains),
            source_description=source_description,
        )

    @staticmethod
    def _compile_host_records(domains):
        compiled = []

        for index, domain in enumerate(domains):
            context = f"Policy domains[{index}]"

            if isinstance(domain, str):
                host = PolicyMatcher._normalize_host_pattern(domain, context)
                compiled.append(
                    HostRecord(
                        host=host,
                        wildcard_suffix=host[2:] if host.startswith("*.") else None,
                        rules=(RuntimeRule(schemes=DEFAULT_RULE_SCHEMES),),
                    )
                )
                continue

            if not isinstance(domain, dict):
                raise PolicyError(
                    f"{context} must be a string or mapping, "
                    f"got {type(domain).__name__}: {domain!r}"
                )

            unknown_keys = sorted(set(domain) - {"host", "rules"})
            if unknown_keys:
                raise PolicyError(f"{context} contains unsupported keys: {unknown_keys}")

            host = PolicyMatcher._normalize_host_pattern(domain.get("host"), f"{context}.host")
            rules = PolicyMatcher._compile_rules(domain.get("rules"), context)
            compiled.append(
                HostRecord(
                    host=host,
                    wildcard_suffix=host[2:] if host.startswith("*.") else None,
                    rules=rules,
                )
            )

        indexed_records = list(enumerate(compiled))
        sorted_records = sorted(
            indexed_records,
            key=lambda item: PolicyMatcher._host_sort_key(item[1].host, item[0]),
        )
        return [record for _, record in sorted_records]

    @staticmethod
    def _normalize_host_pattern(value, context):
        if not isinstance(value, str):
            raise PolicyError(
                f"{context} must be a non-empty string, got {value!r}"
            )

        host = value.strip().lower()
        if not host:
            raise PolicyError(f"{context} must be a non-empty string, got {value!r}")

        if host.startswith("*."):
            suffix = host[2:]
            if not suffix or suffix.startswith(".") or "*" in suffix:
                raise PolicyError(f"{context} has an invalid wildcard host {value!r}")
            return host

        if "*" in host:
            raise PolicyError(
                f"{context} uses unsupported wildcard syntax {value!r}; "
                "only a leading '*.' wildcard is supported"
            )

        return host

    @staticmethod
    def _compile_rules(value, context):
        if not isinstance(value, list):
            raise PolicyError(
                f"{context}.rules must be a YAML list, got {type(value).__name__}: {value!r}"
            )

        if not value:
            raise PolicyError(f"{context}.rules must not be empty")

        return tuple(
            PolicyMatcher._compile_rule(rule, f"{context}.rules[{index}]")
            for index, rule in enumerate(value)
        )

    @staticmethod
    def _compile_rule(rule, context):
        if not isinstance(rule, dict):
            raise PolicyError(
                f"{context} must be a YAML mapping, got {type(rule).__name__}: {rule!r}"
            )

        unknown_keys = sorted(set(rule) - {"schemes", "methods", "path", "query"})
        if unknown_keys:
            raise PolicyError(f"{context} contains unsupported keys: {unknown_keys}")

        schemes_value = rule.get("schemes")
        if not isinstance(schemes_value, list) or not schemes_value:
            raise PolicyError(
                f"{context}.schemes must be a non-empty YAML list, got {schemes_value!r}"
            )

        schemes = []
        for index, scheme in enumerate(schemes_value):
            if not isinstance(scheme, str) or not scheme:
                raise PolicyError(
                    f"{context}.schemes[{index}] must be a non-empty string, got {scheme!r}"
                )
            normalized_scheme = scheme.lower()
            if normalized_scheme not in DEFAULT_RULE_SCHEMES:
                raise PolicyError(
                    f"{context}.schemes[{index}] must be one of {list(DEFAULT_RULE_SCHEMES)}, "
                    f"got {scheme!r}"
                )
            schemes.append(normalized_scheme)

        methods = None
        if "methods" in rule:
            methods_value = rule["methods"]
            if not isinstance(methods_value, list) or not methods_value:
                raise PolicyError(
                    f"{context}.methods must be a non-empty YAML list, got {methods_value!r}"
                )
            normalized_methods = []
            for index, method in enumerate(methods_value):
                if not isinstance(method, str) or not method:
                    raise PolicyError(
                        f"{context}.methods[{index}] must be a non-empty string, got {method!r}"
                    )
                normalized_methods.append(method.upper())
            methods = tuple(sorted(set(normalized_methods)))

        path_exact = None
        path_prefix = None
        if "path" in rule:
            path_value = rule["path"]
            if not isinstance(path_value, dict):
                raise PolicyError(
                    f"{context}.path must be a YAML mapping, got {type(path_value).__name__}: {path_value!r}"
                )
            match_keys = [key for key in ("exact", "prefix") if key in path_value]
            if len(match_keys) != 1:
                raise PolicyError(
                    f"{context}.path must contain exactly one of 'exact' or 'prefix'"
                )
            match_key = match_keys[0]
            match_value = path_value[match_key]
            if not isinstance(match_value, str) or not match_value.startswith("/"):
                raise PolicyError(
                    f"{context}.path.{match_key} must be a string starting with '/', got {match_value!r}"
                )
            if match_key == "exact":
                path_exact = match_value
            else:
                path_prefix = match_value

        query_exact = None
        if "query" in rule:
            query_value = rule["query"]
            if not isinstance(query_value, dict):
                raise PolicyError(
                    f"{context}.query must be a YAML mapping, got {type(query_value).__name__}: {query_value!r}"
                )
            if sorted(query_value) != ["exact"]:
                raise PolicyError(
                    f"{context}.query must contain only the 'exact' matcher"
                )
            exact_value = query_value["exact"]
            if not isinstance(exact_value, dict):
                raise PolicyError(
                    f"{context}.query.exact must be a YAML mapping, got {type(exact_value).__name__}: {exact_value!r}"
                )

            normalized_items = []
            for name in sorted(exact_value):
                if not isinstance(name, str) or not name:
                    raise PolicyError(
                        f"{context}.query.exact keys must be non-empty strings, got {name!r}"
                    )
                values = exact_value[name]
                if not isinstance(values, list):
                    raise PolicyError(
                        f"{context}.query.exact.{name} must be a YAML list of strings, got {values!r}"
                    )
                if not values:
                    raise PolicyError(
                        f"{context}.query.exact.{name} must not be an empty list"
                    )
                normalized_values = []
                for index, item in enumerate(values):
                    if not isinstance(item, str):
                        raise PolicyError(
                            f"{context}.query.exact.{name}[{index}] must be a string, got {item!r}"
                        )
                    normalized_values.append(item)
                normalized_items.append((name, tuple(sorted(normalized_values))))
            query_exact = tuple(normalized_items)

        return RuntimeRule(
            schemes=tuple(sorted(set(schemes))),
            methods=methods,
            path_exact=path_exact,
            path_prefix=path_prefix,
            query_exact=query_exact,
        )

    @staticmethod
    def _host_sort_key(host, original_index):
        if host.startswith("*."):
            return (1, -len(host[2:]), original_index)
        return (0, 0, original_index)

    @staticmethod
    def _normalize_request_target(request_target):
        parsed = urlsplit(request_target)
        path = parsed.path or "/"
        query_map = parse_qs(
            parsed.query,
            keep_blank_values=True,
            strict_parsing=False,
        )
        normalized_query = tuple(
            (name, tuple(sorted(values)))
            for name, values in sorted(query_map.items())
        )
        return path, normalized_query

    def is_allowed(self, host):
        return self._find_host_record(host) is not None

    def _find_host_record(self, host):
        for record in self.host_records:
            if record.matches_host(host):
                return record
        return None

    def evaluate_connect(self, host):
        record = self._find_host_record(host)
        if record is None:
            return PolicyDecision(
                phase="connect",
                action="blocked",
                reason="host_not_allowed",
                host=host,
                scheme="https",
            )

        if record.allows_connect_fast_path("https"):
            return PolicyDecision(
                phase="connect",
                action="allowed",
                reason="connect_fast_path",
                host=host,
                scheme="https",
                matched_host=record.host,
            )

        if record.can_match_scheme("https"):
            return PolicyDecision(
                phase="connect",
                action="allowed",
                reason="connect_inspect_request",
                host=host,
                scheme="https",
                matched_host=record.host,
            )

        return PolicyDecision(
            phase="connect",
            action="blocked",
            reason="https_not_permitted",
            host=host,
            scheme="https",
            matched_host=record.host,
        )

    def evaluate_request(self, host, scheme, method, request_target):
        normalized_scheme = scheme.lower()
        normalized_method = method.upper()
        path, normalized_query = self._normalize_request_target(request_target)
        record = self._find_host_record(host)

        if record is None:
            return PolicyDecision(
                phase="request",
                action="blocked",
                reason="host_not_allowed",
                host=host,
                scheme=normalized_scheme,
                method=normalized_method,
                path=path,
            )

        for rule in record.rules:
            if rule.matches_request(
                normalized_scheme,
                normalized_method,
                path,
                normalized_query,
            ):
                return PolicyDecision(
                    phase="request",
                    action="allowed",
                    reason="request_rule_matched",
                    host=host,
                    scheme=normalized_scheme,
                    matched_host=record.host,
                    method=normalized_method,
                    path=path,
                )

        reason = "scheme_not_permitted"
        if record.can_match_scheme(normalized_scheme):
            reason = "no_rule_matched"

        return PolicyDecision(
            phase="request",
            action="blocked",
            reason=reason,
            host=host,
            scheme=normalized_scheme,
            matched_host=record.host,
            method=normalized_method,
            path=path,
        )
