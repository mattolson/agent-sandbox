"""
Backend-neutral secret resolution for proxy-side header injection.

The first backend is intentionally small: `file:<absolute-root>` maps each
logical secret ID to one direct child file under the root. File-backed secrets
are read at request time. A file created or modified inside an already-mounted
source is visible on the next `resolve()` call without a proxy reload.
"""

from __future__ import annotations

import base64
import errno
import os
import stat
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import policy_injection  # noqa: E402


SECRET_SOURCE_ENV = "AGENTBOX_SECRET_SOURCE"
FILE_SOURCE_SCHEME = "file"
_SECRET_READ_SIZE = 64 * 1024


class SecretResolverError(Exception):
    """Raised when a secret source or requested secret cannot be resolved."""


def _fail_secret(message):
    raise SecretResolverError(message)


@dataclass(frozen=True)
class SecretResolutionContext:
    project: str | None = None
    target: str | None = None


@dataclass(frozen=True)
class SecretResolutionWarning:
    code: str
    message: str
    path: str | None = None

    def __str__(self):
        return self.message


@dataclass(frozen=True, repr=False)
class SecretValue:
    _text: str

    @classmethod
    def from_text(cls, text):
        if not isinstance(text, str):
            raise TypeError("secret text must be a string")
        return cls(text)

    def as_text(self):
        return self._text

    def __repr__(self):
        return "SecretValue(<redacted>)"

    def __str__(self):
        return "<redacted>"


@dataclass(frozen=True)
class SecretResolution:
    secret_id: str
    value: SecretValue
    warnings: tuple[SecretResolutionWarning, ...] = ()


class SecretResolver:
    @classmethod
    def from_env(cls, env=None):
        if env is None:
            env = os.environ
        return cls.from_source(env.get(SECRET_SOURCE_ENV))

    @classmethod
    def from_source(cls, source):
        if source is None or not str(source).strip():
            raise SecretResolverError(
                f"{SECRET_SOURCE_ENV} must be set to a secret source such as "
                "file:/run/agentbox/secrets"
            )

        source_text = str(source).strip()
        scheme, separator, value = source_text.partition(":")
        if not separator:
            raise SecretResolverError(
                f"{SECRET_SOURCE_ENV} must include a source scheme, got {source_text!r}"
            )

        scheme = scheme.lower()
        if scheme != FILE_SOURCE_SCHEME:
            raise SecretResolverError(
                f"Unsupported secret source scheme {scheme!r}; only 'file' is supported"
            )

        root = Path(value.strip())
        return FileSecretResolver(root)

    def resolve(self, secret_id, context=None):
        raise NotImplementedError


class FileSecretResolver(SecretResolver):
    def __init__(self, root):
        root = Path(root)
        if not root.is_absolute():
            raise SecretResolverError(
                f"file secret source root must be an absolute path, got {str(root)!r}"
            )
        self.root = root

    def resolve(self, secret_id, context=None):
        del context
        normalized_id = policy_injection.normalize_secret_id(
            secret_id,
            "secret_id",
            _fail_secret,
        )

        root_stat = self._stat_root()
        warnings = list(
            _permission_warnings(
                self.root,
                root_stat.st_mode,
                subject="secret source directory",
                recommended_mode="700",
            )
        )

        secret_path = self.root / normalized_id
        if secret_path.parent != self.root:
            raise SecretResolverError(
                f"Secret ID {normalized_id!r} does not map to a direct child file"
            )

        file_stat = self._lstat_secret(secret_path, normalized_id)
        warnings.extend(
            _permission_warnings(
                secret_path,
                file_stat.st_mode,
                subject="secret file",
                recommended_mode="600",
            )
        )

        raw_secret = _read_regular_file(secret_path, normalized_id)
        return SecretResolution(
            secret_id=normalized_id,
            value=SecretValue.from_text(_decode_secret_bytes(raw_secret, normalized_id)),
            warnings=tuple(warnings),
        )

    def _stat_root(self):
        try:
            root_stat = self.root.stat()
        except FileNotFoundError:
            raise SecretResolverError(
                f"Secret source root does not exist: {self.root}"
            ) from None
        except PermissionError:
            raise SecretResolverError(
                f"Secret source root is not accessible: {self.root}"
            ) from None

        if not stat.S_ISDIR(root_stat.st_mode):
            raise SecretResolverError(
                f"Secret source root is not a directory: {self.root}"
            )
        return root_stat

    def _lstat_secret(self, secret_path, secret_id):
        try:
            file_stat = secret_path.lstat()
        except FileNotFoundError:
            raise SecretResolverError(
                f"Secret file not found for secret ID {secret_id!r}"
            ) from None
        except PermissionError:
            raise SecretResolverError(
                f"Secret file is not accessible for secret ID {secret_id!r}"
            ) from None

        if stat.S_ISLNK(file_stat.st_mode):
            raise SecretResolverError(
                f"Secret file for secret ID {secret_id!r} must not be a symlink"
            )
        if not stat.S_ISREG(file_stat.st_mode):
            raise SecretResolverError(
                f"Secret file for secret ID {secret_id!r} must be a regular file"
            )
        return file_stat


def _permission_warnings(path, mode, subject, recommended_mode):
    unsafe_bits = stat.S_IMODE(mode) & (
        stat.S_IRGRP | stat.S_IWGRP | stat.S_IROTH | stat.S_IWOTH
    )
    if not unsafe_bits:
        return ()

    display_mode = oct(stat.S_IMODE(mode))
    return (
        SecretResolutionWarning(
            code="unsafe_permissions",
            path=str(path),
            message=(
                f"{subject} has group/other readable or writable permissions "
                f"({display_mode}) at {path}; consider chmod {recommended_mode}"
            ),
        ),
    )


def _read_regular_file(secret_path, secret_id):
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW

    try:
        fd = os.open(secret_path, flags)
    except FileNotFoundError:
        raise SecretResolverError(
            f"Secret file not found for secret ID {secret_id!r}"
        ) from None
    except PermissionError:
        raise SecretResolverError(
            f"Secret file is not readable for secret ID {secret_id!r}"
        ) from None
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            raise SecretResolverError(
                f"Secret file for secret ID {secret_id!r} must not be a symlink"
            ) from None
        raise SecretResolverError(
            f"Secret file could not be opened for secret ID {secret_id!r}: "
            f"{exc.strerror}"
        ) from None

    try:
        opened_stat = os.fstat(fd)
        if not stat.S_ISREG(opened_stat.st_mode):
            raise SecretResolverError(
                f"Secret file for secret ID {secret_id!r} must be a regular file"
            )

        chunks = []
        while True:
            chunk = os.read(fd, _SECRET_READ_SIZE)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def _decode_secret_bytes(raw_secret, secret_id):
    if raw_secret.endswith(b"\r\n"):
        raw_secret = raw_secret[:-2]
    elif raw_secret.endswith(b"\n"):
        raw_secret = raw_secret[:-1]

    if b"\x00" in raw_secret or b"\r" in raw_secret or b"\n" in raw_secret:
        raise SecretResolverError(
            f"Secret file for secret ID {secret_id!r} contains invalid secret bytes"
        )

    try:
        return raw_secret.decode("utf-8")
    except UnicodeDecodeError:
        raise SecretResolverError(
            f"Secret file for secret ID {secret_id!r} must contain UTF-8 text"
        ) from None


def render_header_value(secret_value, transform):
    if not isinstance(secret_value, SecretValue):
        raise SecretResolverError("secret_value must be a SecretValue")

    normalized = policy_injection.normalize_header_transform(
        transform,
        "header",
        _fail_secret,
    )
    secret_text = secret_value.as_text()

    if normalized["type"] == "bearer":
        return f"Bearer {secret_text}"

    if normalized["type"] == "basic":
        username = normalized["username"]
        credentials = f"{username}:{secret_text}".encode("utf-8")
        encoded = base64.b64encode(credentials).decode("ascii")
        return f"Basic {encoded}"

    raise SecretResolverError(
        f"Unsupported header transform type {normalized['type']!r}"
    )
