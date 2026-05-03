import base64
import importlib.util
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SECRET_RESOLVER_PATH = REPO_ROOT / "images" / "proxy" / "secret_resolver.py"


def load_secret_resolver_module():
    loader = SourceFileLoader("secret_resolver_module", str(SECRET_RESOLVER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


class SecretResolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.secret_resolver = load_secret_resolver_module()

    def make_root(self):
        tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(tempdir.cleanup)
        root = Path(tempdir.name)
        root.chmod(0o700)
        return root

    def write_secret(self, root, secret_id="service-token", value=b"secret-token"):
        path = root / secret_id
        path.write_bytes(value)
        path.chmod(0o600)
        return path

    def resolver_for_root(self, root):
        return self.secret_resolver.SecretResolver.from_env(
            {"AGENTBOX_SECRET_SOURCE": f"file:{root}"}
        )

    def test_from_env_resolves_file_secret(self):
        root = self.make_root()
        self.write_secret(root, value=b"secret-token\n")

        result = self.resolver_for_root(root).resolve("service-token")

        self.assertEqual(result.secret_id, "service-token")
        self.assertEqual(result.value.as_text(), "secret-token")
        self.assertEqual(result.warnings, ())

    def test_missing_source_has_actionable_error(self):
        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.secret_resolver.SecretResolver.from_env({})

        self.assertIn("AGENTBOX_SECRET_SOURCE", str(context.exception))
        self.assertIn("file:/run/agentbox/secrets", str(context.exception))

    def test_unsupported_source_scheme_is_rejected(self):
        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.secret_resolver.SecretResolver.from_env(
                {"AGENTBOX_SECRET_SOURCE": "keychain:agentbox"}
            )

        self.assertIn("Unsupported secret source scheme", str(context.exception))
        self.assertIn("file", str(context.exception))

    def test_file_source_root_must_be_absolute(self):
        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.secret_resolver.SecretResolver.from_env(
                {"AGENTBOX_SECRET_SOURCE": "file:relative/secrets"}
            )

        self.assertIn("absolute path", str(context.exception))

    def test_missing_source_root_is_rejected(self):
        root = self.make_root()
        missing = root / "missing"
        resolver = self.resolver_for_root(missing)

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            resolver.resolve("service-token")

        self.assertIn("Secret source root does not exist", str(context.exception))

    def test_source_root_must_be_directory(self):
        root = self.make_root()
        path = root / "not-a-directory"
        path.write_text("not a directory", encoding="utf-8")
        path.chmod(0o600)
        resolver = self.resolver_for_root(path)

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            resolver.resolve("service-token")

        self.assertIn("not a directory", str(context.exception))

    def test_missing_secret_file_is_rejected(self):
        root = self.make_root()

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("missing-token")

        self.assertIn("Secret file not found", str(context.exception))
        self.assertIn("missing-token", str(context.exception))

    def test_path_traversal_secret_id_is_rejected(self):
        root = self.make_root()

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("../token")

        self.assertIn("must match [A-Za-z0-9._-]+", str(context.exception))

    def test_symlink_secret_file_is_rejected(self):
        root = self.make_root()
        outside = root.parent / "outside-secret"
        outside.write_bytes(b"secret-token")
        outside.chmod(0o600)
        self.addCleanup(lambda: outside.exists() and outside.unlink())
        (root / "service-token").symlink_to(outside)

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("service-token")

        self.assertIn("must not be a symlink", str(context.exception))
        self.assertNotIn("secret-token", str(context.exception))

    def test_non_regular_secret_file_is_rejected(self):
        root = self.make_root()
        (root / "service-token").mkdir()

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("service-token")

        self.assertIn("must be a regular file", str(context.exception))

    def test_unsafe_permissions_are_warnings(self):
        root = self.make_root()
        root.chmod(0o755)
        secret_path = self.write_secret(root)
        secret_path.chmod(0o644)

        result = self.resolver_for_root(root).resolve("service-token")

        self.assertEqual(result.value.as_text(), "secret-token")
        self.assertEqual(
            [warning.code for warning in result.warnings],
            ["unsafe_permissions", "unsafe_permissions"],
        )
        messages = "\n".join(str(warning) for warning in result.warnings)
        self.assertIn("chmod 700", messages)
        self.assertIn("chmod 600", messages)
        self.assertNotIn("secret-token", messages)

    def test_file_secret_changes_are_visible_on_next_resolve(self):
        root = self.make_root()
        secret_path = self.write_secret(root, value=b"first-token")
        resolver = self.resolver_for_root(root)

        first = resolver.resolve("service-token")
        secret_path.write_bytes(b"second-token")
        secret_path.chmod(0o600)
        second = resolver.resolve("service-token")

        self.assertEqual(first.value.as_text(), "first-token")
        self.assertEqual(second.value.as_text(), "second-token")

    def test_crlf_trailing_newline_is_trimmed_once(self):
        root = self.make_root()
        self.write_secret(root, value=b"secret-token\r\n")

        result = self.resolver_for_root(root).resolve("service-token")

        self.assertEqual(result.value.as_text(), "secret-token")

    def test_embedded_newline_is_rejected_without_leaking_secret(self):
        root = self.make_root()
        self.write_secret(root, value=b"top-secret\nstill-secret")

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("service-token")

        message = str(context.exception)
        self.assertIn("invalid secret bytes", message)
        self.assertNotIn("top-secret", message)
        self.assertNotIn("still-secret", message)

    def test_nul_byte_is_rejected_without_leaking_secret(self):
        root = self.make_root()
        self.write_secret(root, value=b"top-secret\x00still-secret")

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.resolver_for_root(root).resolve("service-token")

        message = str(context.exception)
        self.assertIn("invalid secret bytes", message)
        self.assertNotIn("top-secret", message)
        self.assertNotIn("still-secret", message)

    def test_secret_value_repr_is_redacted(self):
        value = self.secret_resolver.SecretValue.from_text("secret-token")
        result = self.secret_resolver.SecretResolution("service-token", value)

        self.assertNotIn("secret-token", repr(value))
        self.assertNotIn("secret-token", str(value))
        self.assertNotIn("secret-token", repr(result))
        self.assertIn("redacted", repr(value))

    def test_bearer_transform_renders_authorization_value(self):
        value = self.secret_resolver.SecretValue.from_text("secret-token")

        rendered = self.secret_resolver.render_header_value(
            value,
            {"type": "bearer"},
        )

        self.assertEqual(rendered, "Bearer secret-token")

    def test_basic_transform_renders_authorization_value(self):
        value = self.secret_resolver.SecretValue.from_text("secret-token")

        rendered = self.secret_resolver.render_header_value(
            value,
            {"type": "basic", "username": "x-access-token"},
        )

        expected = base64.b64encode(b"x-access-token:secret-token").decode("ascii")
        self.assertEqual(rendered, f"Basic {expected}")

    def test_transform_validation_reuses_policy_injection_rules(self):
        value = self.secret_resolver.SecretValue.from_text("secret-token")

        with self.assertRaises(self.secret_resolver.SecretResolverError) as context:
            self.secret_resolver.render_header_value(value, {"type": "digest"})

        self.assertIn("transform.type must be one of", str(context.exception))
