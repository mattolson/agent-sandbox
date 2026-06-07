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

import os
import sys
from copy import deepcopy


MODULE_DIR = os.path.dirname(os.path.realpath(__file__))
if MODULE_DIR not in sys.path:
    sys.path.insert(0, MODULE_DIR)

import credential_shim  # noqa: E402
import policy_injection  # noqa: E402


DEFAULT_RULE_SCHEMES = ("http", "https")
READONLY_METHODS = ("GET", "HEAD")
WRITE_METHODS = ("POST",)

SURFACE_API = "api"
SURFACE_GIT = "git"

ACCESS_READ = "read"
ACCESS_READWRITE = "readwrite"
GITHUB_ACCESS_VALUES = (ACCESS_READ, ACCESS_READWRITE)

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
    "hermes": [
        "hermes-agent.nousresearch.com",
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

GIT_UPLOAD_PACK_SERVICE = "git-upload-pack"
GIT_RECEIVE_PACK_SERVICE = "git-receive-pack"
GITHUB_TOKEN_USERNAME = "x-access-token"


RICH_SERVICES = frozenset({"github"})
KNOWN_SERVICES = frozenset(set(SIMPLE_SERVICE_HOSTS.keys()) | RICH_SERVICES)


_COMMON_SERVICE_KEYS = {"name", "merge_mode", "readonly"}
_SERVICE_SPECIFIC_KEYS = {
    "github": {"repos", "git", "api", "surfaces", "access", "auth"},
}


def _build_rule(*, schemes=None, methods=None, path=None, query=None, path_case_insensitive=False):
    rule = {"schemes": list(schemes or DEFAULT_RULE_SCHEMES)}
    if methods is not None:
        rule["methods"] = list(methods)
    if path is not None:
        rule["path"] = dict(path)
        if path_case_insensitive:
            rule["path_case_insensitive"] = True
    if query is not None:
        rule["query"] = deepcopy(query)
    return rule


def _catch_all_rule(readonly):
    if readonly:
        return _build_rule(methods=list(READONLY_METHODS))
    return _build_rule()


def _host_record(host, rules):
    return {"host": host, "rules": [dict(rule) for rule in rules]}


def _apply_rule_transform(rules, transform):
    if transform is None:
        return rules
    transformed = []
    for rule in rules:
        transformed_rule = dict(rule)
        transformed_rule["transform"] = deepcopy(transform)
        transformed.append(transformed_rule)
    return transformed


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


def _normalize_access(value, context, fail):
    access = _require_string(value, context, fail).lower()
    if access not in GITHUB_ACCESS_VALUES:
        fail(
            f"{context} must be one of {list(GITHUB_ACCESS_VALUES)}, "
            f"got {value!r}"
        )
    return access


def _normalize_github_git_auth(value, context, fail):
    if not isinstance(value, dict):
        fail(
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}"
        )

    unknown_keys = sorted(set(value) - {"secret", "client_shim"})
    if unknown_keys:
        fail(f"{context} contains unsupported keys: {unknown_keys}")
    if "secret" not in value:
        fail(f"{context} must contain 'secret'")

    normalized = {
        "secret": policy_injection.normalize_secret_id(
            value["secret"],
            f"{context}.secret",
            fail,
        )
    }
    if "client_shim" in value:
        normalized["client_shim"] = credential_shim.normalize_credential_shim_config(
            value["client_shim"],
            f"{context}.client_shim",
            fail,
        )
    return normalized


def _normalize_github_surface(value, context, fail, *, allow_auth):
    if not isinstance(value, dict):
        fail(
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}"
        )

    supported_keys = {"access", "auth"}
    unknown_keys = sorted(set(value) - supported_keys)
    if unknown_keys:
        fail(f"{context} contains unsupported keys: {unknown_keys}")
    if "access" not in value:
        fail(f"{context} must contain 'access'")

    normalized = {
        "access": _normalize_access(value["access"], f"{context}.access", fail),
    }

    if "auth" in value:
        if not allow_auth:
            fail(f"{context}.auth is not supported yet")
        normalized["auth"] = _normalize_github_git_auth(
            value["auth"],
            f"{context}.auth",
            fail,
        )

    return normalized


def _github_auth_transform(secret_id, context, fail, *, on_existing_header="fail"):
    return policy_injection.normalize_rule_transform(
        {
            "request": {
                "headers": {
                    "Authorization": {
                        "secret": secret_id,
                        "transform": {
                            "type": "basic",
                            "username": GITHUB_TOKEN_USERNAME,
                        },
                    },
                },
                "on_existing_header": on_existing_header,
            },
        },
        context,
        fail,
    )


def _normalize_github_mapping_entry(entry, context, fail):
    merge_mode = _normalize_merge_mode(entry.get("merge_mode", MISSING), context, fail)

    if "access" in entry:
        fail(f"{context}.access is not supported; use git.access or api.access")
    if "auth" in entry:
        fail(f"{context}.auth is not supported; use git.auth")
    if "surfaces" in entry:
        fail(f"{context}.surfaces is not supported; use git or api mappings")

    repos_present = "repos" in entry
    git_present = SURFACE_GIT in entry
    api_present = SURFACE_API in entry

    if repos_present:
        if "readonly" in entry:
            fail(f"{context}.readonly is not supported for repo-scoped github entries")
        if not git_present and not api_present:
            fail(f"{context} must set at least one of 'git' or 'api' when 'repos' is set")

        options = {
            "repos": _normalize_repo_list(entry["repos"], context, fail),
            "surface_configs": {},
        }
        if git_present:
            git = _normalize_github_surface(
                entry[SURFACE_GIT],
                f"{context}.git",
                fail,
                allow_auth=True,
            )
            if git["access"] == ACCESS_READWRITE and "auth" not in git:
                fail(f"{context}.git.auth is required when git.access is 'readwrite'")
            if "auth" in git:
                on_existing_header = "fail"
                if "client_shim" in git["auth"]:
                    on_existing_header = "replace"
                    git["credential_shim_hints"] = [
                        credential_shim.make_github_git_askpass_hint(
                            git["auth"]["secret"],
                            f"{context}.git.auth.client_shim",
                            fail,
                        )
                    ]
                git["transform"] = _github_auth_transform(
                    git["auth"]["secret"],
                    f"{context}.git.auth.transform",
                    fail,
                    on_existing_header=on_existing_header,
                )
            options["surface_configs"][SURFACE_GIT] = git
        if api_present:
            options["surface_configs"][SURFACE_API] = _normalize_github_surface(
                entry[SURFACE_API],
                f"{context}.api",
                fail,
                allow_auth=False,
            )
        return {"name": "github", "merge_mode": merge_mode, "options": options}

    if git_present or api_present:
        fail(f"{context} must set 'repos' when 'git' or 'api' is set")

    readonly = _normalize_readonly(entry.get("readonly", MISSING), context, fail)
    return {
        "name": "github",
        "merge_mode": merge_mode,
        "options": {"readonly": readonly},
    }


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

    if name == "github":
        return _normalize_github_mapping_entry(entry, context, fail)

    merge_mode = _normalize_merge_mode(entry.get("merge_mode", MISSING), context, fail)
    readonly = _normalize_readonly(entry.get("readonly", MISSING), context, fail)
    options = {"readonly": readonly}
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


def _github_api_rules_for_repo(owner, name, access):
    # GitHub treats the owner/repo segment case-insensitively, so the generated
    # paths (built from the lowercased owner/name) are matched case-insensitively
    # to avoid blocking requests that use the repo's canonical mixed case.
    base = f"/repos/{owner}/{name}"
    methods = list(READONLY_METHODS) if access == ACCESS_READ else None
    return [
        _build_rule(methods=methods, path={"exact": base}, path_case_insensitive=True),
        _build_rule(methods=methods, path={"prefix": base + "/"}, path_case_insensitive=True),
    ]


def _github_smart_http_pair(base, git_service):
    return [
        _build_rule(
            methods=list(READONLY_METHODS),
            path={"exact": base + "/info/refs"},
            query={"exact": {"service": [git_service]}},
            path_case_insensitive=True,
        ),
        _build_rule(
            methods=list(WRITE_METHODS),
            path={"exact": f"{base}/{git_service}"},
            path_case_insensitive=True,
        ),
    ]


def _github_git_rules_for_repo(owner, name, access, transform=None):
    base = f"/{owner}/{name}.git"
    # git-upload-pack POST transfers clone/fetch pack data; it does not grant
    # push/write access. git-receive-pack is the write-capable path.
    rules = list(_github_smart_http_pair(base, GIT_UPLOAD_PACK_SERVICE))
    if access == ACCESS_READWRITE:
        rules.extend(_github_smart_http_pair(base, GIT_RECEIVE_PACK_SERVICE))
    return _apply_rule_transform(rules, transform)


def _expand_github_service(options):
    readonly = options.get("readonly", False)
    repos = options.get("repos")
    surface_configs = options.get("surface_configs", {})

    if not repos:
        return [
            _host_record(host, [_catch_all_rule(readonly=readonly)])
            for host in GITHUB_DEFAULT_HOSTS
        ]

    records = []

    if SURFACE_API in surface_configs:
        access = surface_configs[SURFACE_API]["access"]
        api_rules = []
        for owner, name in repos:
            api_rules.extend(_github_api_rules_for_repo(owner, name, access))
        records.append(_host_record(GITHUB_API_HOST, api_rules))

    if SURFACE_GIT in surface_configs:
        git_options = surface_configs[SURFACE_GIT]
        transform = git_options.get("transform")
        git_rules = []
        for owner, name in repos:
            git_rules.extend(
                _github_git_rules_for_repo(
                    owner,
                    name,
                    git_options["access"],
                    transform=transform,
                )
            )
        records.append(_host_record(GITHUB_GIT_HOST, git_rules))

    return records


def _github_credential_shim_hints(options):
    surface_configs = options.get("surface_configs", {})
    git_options = surface_configs.get(SURFACE_GIT, {})
    return list(git_options.get("credential_shim_hints", []))


def expand_service_entry(entry, context, fail):
    normalized = normalize_service_entry(entry, context, fail)
    name = normalized["name"]
    options = normalized["options"]

    if name == "github":
        records = _expand_github_service(options)
        credential_shim_hints = _github_credential_shim_hints(options)
    else:
        records = _expand_simple_service(name, options)
        credential_shim_hints = []

    return {
        "name": name,
        "merge_mode": normalized["merge_mode"],
        "records": records,
        "credential_shim": credential_shim_hints,
    }
