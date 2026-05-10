"""
Agent-visible credential shim metadata for proxy-managed credential flows.

The service catalog emits these hints for clients that need fake credential
setup before the proxy can replace outbound request headers with real secrets.
Hints may include fake credential values and logical secret IDs, but never
resolved secret values.
"""

import json
import os
import shlex

import policy_injection


CREDENTIAL_SHIM_VERSION = 1
CREDENTIAL_SHIM_KEY = "credential_shim"

KIND_GIT_ASKPASS = "git-askpass"
SUPPORTED_KINDS = (KIND_GIT_ASKPASS,)

GITHUB_SERVICE = "github"
GIT_SURFACE = "git"
GITHUB_HOST = "github.com"
GITHUB_TOKEN_USERNAME = "x-access-token"

GIT_FAKE_PASSWORD = "agentbox-proxy-managed"
GIT_ASKPASS_PATH = "/usr/local/bin/agentbox-git-askpass"

DEFAULT_CREDENTIAL_SHIM_INIT_PATH = "/run/agentbox/credential-shims/init.zsh"
GIT_ASKPASS_ENV_RELATIVE_PATH = "git-askpass/env.zsh"


class CredentialShimError(Exception):
    """Raised when credential shim metadata cannot be rendered safely."""


def _default_fail(message):
    raise CredentialShimError(message)


def _fail(fail, message):
    fail(message)


def _normalize_string(value, context, fail):
    if not isinstance(value, str):
        _fail(fail, f"{context} must be a string, got {type(value).__name__}: {value!r}")
    normalized = value.strip()
    if not normalized:
        _fail(fail, f"{context} must not be empty")
    return normalized


def normalize_credential_shim_config(value, context, fail=_default_fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )

    unknown_keys = sorted(set(value) - {"kind"})
    if unknown_keys:
        _fail(fail, f"{context} contains unsupported keys: {unknown_keys}")
    if "kind" not in value:
        _fail(fail, f"{context} must contain 'kind'")

    kind = _normalize_string(value["kind"], f"{context}.kind", fail).lower()
    if kind not in SUPPORTED_KINDS:
        _fail(
            fail,
            f"{context}.kind must be one of {list(SUPPORTED_KINDS)}, "
            f"got {value['kind']!r}",
        )
    return {"kind": kind}


def make_github_git_askpass_hint(secret_id, context, fail=_default_fail):
    normalized_secret = policy_injection.normalize_secret_id(
        secret_id,
        f"{context}.secret",
        fail,
    )
    return normalize_hint(
        {
            "service": GITHUB_SERVICE,
            "surface": GIT_SURFACE,
            "kind": KIND_GIT_ASKPASS,
            "host": GITHUB_HOST,
            "username": GITHUB_TOKEN_USERNAME,
            "fake_password": GIT_FAKE_PASSWORD,
            "secrets": [normalized_secret],
        },
        context,
        fail,
    )


def normalize_hint(value, context, fail=_default_fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )

    supported_keys = {
        "service",
        "surface",
        "kind",
        "host",
        "username",
        "fake_password",
        "secrets",
    }
    unknown_keys = sorted(set(value) - supported_keys)
    if unknown_keys:
        _fail(fail, f"{context} contains unsupported keys: {unknown_keys}")

    required_keys = supported_keys
    missing = sorted(required_keys - set(value))
    if missing:
        _fail(fail, f"{context} must contain keys: {missing}")

    kind = _normalize_string(value["kind"], f"{context}.kind", fail).lower()
    if kind not in SUPPORTED_KINDS:
        _fail(
            fail,
            f"{context}.kind must be one of {list(SUPPORTED_KINDS)}, "
            f"got {value['kind']!r}",
        )

    secrets = value["secrets"]
    if not isinstance(secrets, list):
        _fail(
            fail,
            f"{context}.secrets must be a YAML list, got "
            f"{type(secrets).__name__}: {secrets!r}",
        )
    if not secrets:
        _fail(fail, f"{context}.secrets must not be empty")

    normalized_secrets = []
    seen_secrets = set()
    for index, secret in enumerate(secrets):
        normalized_secret = policy_injection.normalize_secret_id(
            secret,
            f"{context}.secrets[{index}]",
            fail,
        )
        if normalized_secret in seen_secrets:
            continue
        seen_secrets.add(normalized_secret)
        normalized_secrets.append(normalized_secret)

    return {
        "service": _normalize_string(value["service"], f"{context}.service", fail).lower(),
        "surface": _normalize_string(value["surface"], f"{context}.surface", fail).lower(),
        "kind": kind,
        "host": _normalize_string(value["host"], f"{context}.host", fail).lower(),
        "username": _normalize_string(value["username"], f"{context}.username", fail),
        "fake_password": _normalize_string(
            value["fake_password"],
            f"{context}.fake_password",
            fail,
        ),
        "secrets": normalized_secrets,
    }


def dedupe_hints(hints, fail=_default_fail):
    normalized = []
    seen = set()
    for index, hint in enumerate(hints or []):
        normalized_hint = normalize_hint(hint, f"credential_shim.hints[{index}]", fail)
        identity = json.dumps(normalized_hint, sort_keys=True, separators=(",", ":"))
        if identity in seen:
            continue
        seen.add(identity)
        normalized.append(normalized_hint)
    return normalized


def payload_from_hints(hints, fail=_default_fail):
    normalized_hints = dedupe_hints(hints, fail)
    return {
        "version": CREDENTIAL_SHIM_VERSION,
        "hints": normalized_hints,
    }


def hints_from_payload(payload, fail=_default_fail):
    if payload is None:
        return []
    if not isinstance(payload, dict):
        _fail(
            fail,
            f"credential_shim must be a YAML mapping, got "
            f"{type(payload).__name__}: {payload!r}",
        )
    version = payload.get("version")
    if version != CREDENTIAL_SHIM_VERSION:
        _fail(
            fail,
            f"credential_shim.version must be {CREDENTIAL_SHIM_VERSION}, got {version!r}",
        )
    return dedupe_hints(payload.get("hints") or [], fail)


def _git_askpass_hints(hints):
    return [
        hint for hint in hints
        if hint["service"] == GITHUB_SERVICE
        and hint["surface"] == GIT_SURFACE
        and hint["kind"] == KIND_GIT_ASKPASS
    ]


def render_git_askpass_fragment_from_hints(hints):
    lines = [
        "# Generated by agentbox. Contains fake git-askpass credential values only.",
    ]
    git_askpass_hints = _git_askpass_hints(hints)
    if not git_askpass_hints:
        lines.append("# No git-askpass credential shim is active.")
        return "\n".join(lines) + "\n"

    hint = git_askpass_hints[0]
    exports = {
        "AGENTBOX_GIT_FAKE_USERNAME": hint["username"],
        "AGENTBOX_GIT_FAKE_PASSWORD": hint["fake_password"],
        "GIT_ASKPASS": GIT_ASKPASS_PATH,
        "GIT_TERMINAL_PROMPT": "0",
    }
    for name, value in exports.items():
        lines.append(f"export {name}={shlex.quote(value)}")
    return "\n".join(lines) + "\n"


def render_init_fragment_from_hints(init_path, hints):
    lines = [
        "# Generated by agentbox. Sources active credential shim fragments.",
    ]
    if _git_askpass_hints(hints):
        base_dir = os.path.dirname(init_path)
        git_askpass_path = os.path.join(base_dir, GIT_ASKPASS_ENV_RELATIVE_PATH)
        quoted_path = shlex.quote(git_askpass_path)
        lines.extend(
            [
                f"if [ -f {quoted_path} ]; then",
                f"  source {quoted_path}",
                "fi",
            ]
        )
    else:
        lines.append("# No credential shims are active.")
    return "\n".join(lines) + "\n"


def render_init_fragment(init_path, payload=None, fail=_default_fail):
    return render_init_fragment_from_hints(
        init_path,
        hints_from_payload(payload, fail),
    )


def render_git_askpass_fragment(payload=None, fail=_default_fail):
    return render_git_askpass_fragment_from_hints(
        hints_from_payload(payload, fail),
    )


def _write_file(path, body):
    if not path:
        return

    output_dir = os.path.dirname(path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        handle.write(body)
    os.chmod(tmp_path, 0o644)
    os.replace(tmp_path, path)


def write_init(init_path, payload=None, fail=_default_fail):
    if not init_path:
        return

    hints = hints_from_payload(payload, fail)
    base_dir = os.path.dirname(init_path)
    git_askpass_path = os.path.join(base_dir, GIT_ASKPASS_ENV_RELATIVE_PATH)

    _write_file(
        git_askpass_path,
        render_git_askpass_fragment_from_hints(hints),
    )
    _write_file(
        init_path,
        render_init_fragment_from_hints(init_path, hints),
    )
