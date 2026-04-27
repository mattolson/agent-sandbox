"""
Semantic service catalog for render-policy.

Service entries in proxy policy are authored as either a plain string or a
mapping with a required `name`. Plain strings preserve the simple host-wide
expansion behavior. Mappings can request narrower service-specific expansions
such as repo-scoped GitHub access.

The catalog validates each entry and emits canonical host-record fragments
that are fed through the same merge pipeline the renderer already uses for
authored `domains` entries.
"""

from copy import deepcopy


DEFAULT_RULE_SCHEMES = ("http", "https")
READONLY_METHODS = ("GET", "HEAD")
WRITE_METHODS = ("POST",)

SURFACE_API = "api"
SURFACE_GIT = "git"

MERGE_MODE_REPLACE = "replace"

MISSING = object()


SIMPLE_SERVICE_HOSTS = {
    "claude": [
        "*.anthropic.com",
        "*.claude.ai",
        "*.claude.com",
    ],
    "codex": [
        "*.openai.com",
        "chatgpt.com",
        "*.chatgpt.com",
    ],
    "factory": [
        "api.factory.ai",
        "api.workos.com",
    ],
    "gemini": [
        "cloudcode-pa.googleapis.com",
        "generativelanguage.googleapis.com",
        "oauth2.googleapis.com",
    ],
    "opencode": [
        "opencode.ai",
        "*.opencode.ai",
        "models.dev",
    ],
    "pi": [],
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
    "jetbrains-ai": [
        "api.jetbrains.ai",
        "api.app.prod.grazie.aws.intellij.net",
        "www.jetbrains.com",
        "account.jetbrains.com",
        "oauth.account.jetbrains.com",
        "frameworks.jetbrains.com",
        "cloudconfig.jetbrains.com",
        "download.jetbrains.com",
        "download-cf.jetbrains.com",
        "download-cdn.jetbrains.com",
        "resources.jetbrains.com",
        "cdn.agentclientprotocol.com",
    ],
}


GITHUB_DEFAULT_HOSTS = (
    "github.com",
    "*.github.com",
    "githubusercontent.com",
    "*.githubusercontent.com",
)

GITHUB_API_HOST = "api.github.com"
GITHUB_GIT_HOST = "github.com"
GITHUB_SURFACES = (SURFACE_API, SURFACE_GIT)

GIT_UPLOAD_PACK_SERVICE = "git-upload-pack"
GIT_RECEIVE_PACK_SERVICE = "git-receive-pack"


RICH_SERVICES = frozenset({"github"})
KNOWN_SERVICES = frozenset(set(SIMPLE_SERVICE_HOSTS.keys()) | RICH_SERVICES)


_COMMON_SERVICE_KEYS = {"name", "merge_mode", "readonly"}
_SERVICE_SPECIFIC_KEYS = {
    "github": {"repos", "surfaces"},
}


def _build_rule(*, schemes=None, methods=None, path=None, query=None):
    rule = {"schemes": list(schemes or DEFAULT_RULE_SCHEMES)}
    if methods is not None:
        rule["methods"] = list(methods)
    if path is not None:
        rule["path"] = dict(path)
    if query is not None:
        rule["query"] = deepcopy(query)
    return rule


def _catch_all_rule(readonly):
    if readonly:
        return _build_rule(methods=list(READONLY_METHODS))
    return _build_rule()


def _host_record(host, rules):
    return {"host": host, "rules": [dict(rule) for rule in rules]}


def _require_string(value, context, fail):
    if not isinstance(value, str):
        fail(f"{context} must be a string, got {type(value).__name__}: {value!r}")
    normalized = value.strip()
    if not normalized:
        fail(f"{context} must not be empty")
    return normalized


def _normalize_service_name(value, context, fail):
    name = _require_string(value, context, fail).lower()
    if name not in KNOWN_SERVICES:
        fail(
            f"{context} references unknown service {name!r}; "
            f"expected one of {sorted(KNOWN_SERVICES)}"
        )
    return name


def _normalize_merge_mode(value, context, fail):
    if value is MISSING:
        return None
    merge_mode = _require_string(value, f"{context}.merge_mode", fail).lower()
    if merge_mode != MERGE_MODE_REPLACE:
        fail(
            f"{context}.merge_mode must be '{MERGE_MODE_REPLACE}' when set, "
            f"got {value!r}"
        )
    return merge_mode


def _normalize_readonly(value, context, fail):
    if value is MISSING:
        return False
    if not isinstance(value, bool):
        fail(
            f"{context}.readonly must be a boolean, got "
            f"{type(value).__name__}: {value!r}"
        )
    return bool(value)


_REPO_PART_INVALID_CHARS = ("/", "?", "#", "\\", " ", "\t")


def _normalize_repo_list(value, context, fail):
    if not isinstance(value, list):
        fail(
            f"{context}.repos must be a YAML list, got "
            f"{type(value).__name__}: {value!r}"
        )
    if not value:
        fail(f"{context}.repos must not be empty when set")

    normalized = []
    seen = set()
    for index, item in enumerate(value):
        raw = _require_string(item, f"{context}.repos[{index}]", fail)
        parts = raw.split("/")
        if len(parts) != 2 or not parts[0] or not parts[1]:
            fail(
                f"{context}.repos[{index}] must be in 'owner/name' form, "
                f"got {raw!r}"
            )
        owner, name = parts
        for part, label in ((owner, "owner"), (name, "name")):
            for character in _REPO_PART_INVALID_CHARS:
                if character in part:
                    fail(
                        f"{context}.repos[{index}] {label} contains invalid "
                        f"character {character!r}: {raw!r}"
                    )
        owner = owner.lower()
        name = name.lower()
        identifier = f"{owner}/{name}"
        if identifier in seen:
            continue
        seen.add(identifier)
        normalized.append((owner, name))
    return normalized


def _normalize_surface_list(value, context, fail, allowed):
    if not isinstance(value, list):
        fail(
            f"{context}.surfaces must be a YAML list, got "
            f"{type(value).__name__}: {value!r}"
        )
    if not value:
        fail(f"{context}.surfaces must not be empty when set")

    seen = set()
    ordered = []
    for index, item in enumerate(value):
        name = _require_string(item, f"{context}.surfaces[{index}]", fail).lower()
        if name not in allowed:
            fail(
                f"{context}.surfaces[{index}] must be one of "
                f"{sorted(allowed)}, got {item!r}"
            )
        if name in seen:
            continue
        seen.add(name)
        ordered.append(name)
    return ordered


def _normalize_mapping_entry(entry, context, fail):
    if "name" not in entry:
        fail(f"{context} must contain 'name'")
    name = _normalize_service_name(entry["name"], f"{context}.name", fail)

    allowed_keys = _COMMON_SERVICE_KEYS | _SERVICE_SPECIFIC_KEYS.get(name, set())
    unknown_keys = sorted(set(entry) - allowed_keys)
    if unknown_keys:
        fail(
            f"{context} contains unsupported keys for service {name!r}: "
            f"{unknown_keys}"
        )

    merge_mode = _normalize_merge_mode(entry.get("merge_mode", MISSING), context, fail)
    readonly = _normalize_readonly(entry.get("readonly", MISSING), context, fail)

    options = {"readonly": readonly}

    if name == "github":
        repos_value = entry.get("repos", MISSING)
        surfaces_value = entry.get("surfaces", MISSING)

        if repos_value is not MISSING and surfaces_value is MISSING:
            fail(f"{context} must set 'surfaces' when 'repos' is set")
        if surfaces_value is not MISSING and repos_value is MISSING:
            fail(f"{context} must set 'repos' when 'surfaces' is set")

        if repos_value is not MISSING:
            options["repos"] = _normalize_repo_list(repos_value, context, fail)
            options["surfaces"] = _normalize_surface_list(
                surfaces_value, context, fail, allowed=GITHUB_SURFACES
            )

    return {"name": name, "merge_mode": merge_mode, "options": options}


def normalize_service_entry(entry, context, fail):
    if isinstance(entry, str):
        name = _normalize_service_name(entry, context, fail)
        return {"name": name, "merge_mode": None, "options": {"readonly": False}}

    if not isinstance(entry, dict):
        fail(
            f"{context} must be either a string service name or a YAML mapping, "
            f"got {type(entry).__name__}: {entry!r}"
        )

    return _normalize_mapping_entry(entry, context, fail)


def _expand_simple_service(name, options):
    readonly = options.get("readonly", False)
    hosts = SIMPLE_SERVICE_HOSTS[name]
    return [
        _host_record(host, [_catch_all_rule(readonly=readonly)])
        for host in hosts
    ]


def _github_api_rules_for_repo(owner, name, readonly):
    base = f"/repos/{owner}/{name}"
    methods = list(READONLY_METHODS) if readonly else None
    return [
        _build_rule(methods=methods, path={"exact": base}),
        _build_rule(methods=methods, path={"prefix": base + "/"}),
    ]


def _github_smart_http_pair(base, git_service):
    return [
        _build_rule(
            methods=list(READONLY_METHODS),
            path={"exact": base + "/info/refs"},
            query={"exact": {"service": [git_service]}},
        ),
        _build_rule(
            methods=list(WRITE_METHODS),
            path={"exact": f"{base}/{git_service}"},
        ),
    ]


def _github_git_rules_for_repo(owner, name, readonly):
    base = f"/{owner}/{name}.git"
    # git-upload-pack POST transfers clone/fetch pack data; it does not grant
    # push/write access. git-receive-pack is the write-capable path.
    rules = list(_github_smart_http_pair(base, GIT_UPLOAD_PACK_SERVICE))
    if not readonly:
        rules.extend(_github_smart_http_pair(base, GIT_RECEIVE_PACK_SERVICE))
    return rules


def _expand_github_service(options):
    readonly = options.get("readonly", False)
    repos = options.get("repos")
    surfaces = options.get("surfaces")

    if not repos:
        return [
            _host_record(host, [_catch_all_rule(readonly=readonly)])
            for host in GITHUB_DEFAULT_HOSTS
        ]

    records = []

    if SURFACE_API in surfaces:
        api_rules = []
        for owner, name in repos:
            api_rules.extend(_github_api_rules_for_repo(owner, name, readonly))
        records.append(_host_record(GITHUB_API_HOST, api_rules))

    if SURFACE_GIT in surfaces:
        git_rules = []
        for owner, name in repos:
            git_rules.extend(_github_git_rules_for_repo(owner, name, readonly))
        records.append(_host_record(GITHUB_GIT_HOST, git_rules))

    return records


def expand_service_entry(entry, context, fail):
    normalized = normalize_service_entry(entry, context, fail)
    name = normalized["name"]
    options = normalized["options"]

    if name == "github":
        records = _expand_github_service(options)
    else:
        records = _expand_simple_service(name, options)

    return {
        "name": name,
        "merge_mode": normalized["merge_mode"],
        "records": records,
    }
