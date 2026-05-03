"""
Validation helpers for rule-scoped proxy secret injection metadata.

Policy authors configure injection at higher-level authoring surfaces. The
renderer stores the normalized form directly on emitted rules so matching and
future request mutation can stay service-agnostic.
"""

import re


SECRET_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")
HEADER_NAME_PATTERN = re.compile(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")
INJECT_TRANSFORMS = ("basic", "bearer")
ON_EXISTING_HEADER_VALUES = ("fail", "replace")


def _fail(fail, message):
    fail(message)


def normalize_string(value, context, fail):
    if not isinstance(value, str):
        _fail(fail, f"{context} must be a string, got {type(value).__name__}: {value!r}")

    normalized = value.strip()
    if not normalized:
        _fail(fail, f"{context} must not be empty")

    return normalized


def normalize_secret_id(value, context, fail):
    secret_id = normalize_string(value, context, fail)
    if not SECRET_ID_PATTERN.fullmatch(secret_id):
        _fail(
            fail,
            f"{context} must match [A-Za-z0-9._-]+, got {value!r}",
        )
    return secret_id


def normalize_header_name(value, context, fail):
    header = normalize_string(value, context, fail)
    if not HEADER_NAME_PATTERN.fullmatch(header):
        _fail(fail, f"{context} must be a valid HTTP header name, got {value!r}")
    return header


def normalize_header_transform(value, context, fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context}.transform must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )

    if "type" not in value:
        _fail(fail, f"{context}.transform must contain 'type'")

    transform_type = normalize_string(
        value["type"],
        f"{context}.transform.type",
        fail,
    ).lower()
    if transform_type not in INJECT_TRANSFORMS:
        _fail(
            fail,
            f"{context}.transform.type must be one of {list(INJECT_TRANSFORMS)}, "
            f"got {value['type']!r}",
        )

    if transform_type == "basic":
        unknown_keys = sorted(set(value) - {"type", "username"})
        if unknown_keys:
            _fail(fail, f"{context}.transform contains unsupported keys: {unknown_keys}")
        if "username" not in value:
            _fail(fail, f"{context}.transform.username is required for basic transform")
        return {
            "type": "basic",
            "username": normalize_string(
                value["username"],
                f"{context}.transform.username",
                fail,
            ),
        }

    unknown_keys = sorted(set(value) - {"type"})
    if unknown_keys:
        _fail(fail, f"{context}.transform contains unsupported keys: {unknown_keys}")
    return {"type": "bearer"}


def normalize_inject_header(value, context, fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )

    unknown_keys = sorted(set(value) - {"secret", "transform"})
    if unknown_keys:
        _fail(fail, f"{context} contains unsupported keys: {unknown_keys}")

    if "secret" not in value:
        _fail(fail, f"{context} must contain 'secret'")
    if "transform" not in value:
        _fail(fail, f"{context} must contain 'transform'")

    return {
        "secret": normalize_secret_id(value["secret"], f"{context}.secret", fail),
        "transform": normalize_header_transform(value["transform"], context, fail),
    }


def normalize_inject_headers(value, context, fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context}.headers must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )
    if not value:
        _fail(fail, f"{context}.headers must not be empty")

    normalized = {}
    normalized_names = {}
    for raw_name in sorted(value, key=lambda item: str(item)):
        header = normalize_header_name(raw_name, f"{context}.headers key", fail)
        header_key = header.lower()
        if header_key in normalized_names:
            _fail(
                fail,
                f"{context}.headers contains duplicate header names "
                f"{normalized_names[header_key]!r} and {raw_name!r}",
            )
        normalized_names[header_key] = raw_name
        normalized[header] = normalize_inject_header(
            value[raw_name],
            f"{context}.headers.{header}",
            fail,
        )

    return normalized


def normalize_on_existing_header(value, context, fail):
    action = normalize_string(value, f"{context}.on_existing_header", fail).lower()
    if action not in ON_EXISTING_HEADER_VALUES:
        _fail(
            fail,
            f"{context}.on_existing_header must be one of "
            f"{list(ON_EXISTING_HEADER_VALUES)}, got {value!r}",
        )
    return action


def normalize_inject(value, context, fail):
    if not isinstance(value, dict):
        _fail(
            fail,
            f"{context} must be a YAML mapping, got "
            f"{type(value).__name__}: {value!r}",
        )

    unknown_keys = sorted(set(value) - {"headers", "on_existing_header"})
    if unknown_keys:
        _fail(fail, f"{context} contains unsupported keys: {unknown_keys}")

    if "headers" not in value:
        _fail(fail, f"{context} must contain 'headers'")

    return {
        "headers": normalize_inject_headers(value["headers"], context, fail),
        "on_existing_header": normalize_on_existing_header(
            value.get("on_existing_header", "fail"),
            context,
            fail,
        ),
    }
