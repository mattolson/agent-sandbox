import importlib.util
import sys
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SERVICE_CATALOG_PATH = REPO_ROOT / "images" / "proxy" / "service_catalog.py"


def load_service_catalog_module():
    loader = SourceFileLoader("service_catalog_module", str(SERVICE_CATALOG_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


class _CatalogFailure(Exception):
    pass


def _fail(message):
    raise _CatalogFailure(message)


def expected_github_auth_transform(secret="github-token"):
    return {
        "request": {
            "headers": {
                "Authorization": {
                    "secret": secret,
                    "transform": {
                        "type": "basic",
                        "username": "x-access-token",
                    },
                },
            },
            "on_existing_header": "fail",
        },
    }


class ServiceCatalogNormalizeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_service_catalog_module()

    def test_plain_string_normalizes_to_name_with_readonly_false(self):
        result = self.catalog.normalize_service_entry("github", "ctx", _fail)

        self.assertEqual(result["name"], "github")
        self.assertIsNone(result["merge_mode"])
        self.assertEqual(result["options"], {"readonly": False})

    def test_mapping_entry_requires_name(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry({}, "ctx", _fail)
        self.assertIn("must contain 'name'", str(caught.exception))

    def test_mapping_with_unknown_service_key_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "claude", "repos": ["owner/repo"]},
                "ctx",
                _fail,
            )
        self.assertIn("unsupported keys for service 'claude'", str(caught.exception))

    def test_unknown_service_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry("not-a-service", "ctx", _fail)
        self.assertIn("unknown service", str(caught.exception))

    def test_github_repos_without_surface_mapping_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "repos": ["owner/repo"]},
                "ctx",
                _fail,
            )
        self.assertIn("at least one of 'git' or 'api'", str(caught.exception))

    def test_github_surface_mapping_without_repos_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "git": {"access": "read"}},
                "ctx",
                _fail,
            )
        self.assertIn("must set 'repos' when 'git' or 'api' is set", str(caught.exception))

    def test_github_surfaces_field_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "repos": ["owner/repo"], "surfaces": ["git"]},
                "ctx",
                _fail,
            )
        self.assertIn("surfaces is not supported", str(caught.exception))

    def test_github_repo_scoped_readonly_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "readonly": True,
                    "git": {"access": "read"},
                },
                "ctx",
                _fail,
            )
        self.assertIn("readonly is not supported", str(caught.exception))

    def test_invalid_repo_shape_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "repos": ["owner-only"], "api": {"access": "read"}},
                "ctx",
                _fail,
            )
        self.assertIn("'owner/name' form", str(caught.exception))

    def test_github_repo_names_are_normalized_to_lowercase(self):
        result = self.catalog.normalize_service_entry(
            {"name": "github", "repos": ["MyOrg/MyRepo"], "api": {"access": "read"}},
            "ctx",
            _fail,
        )
        self.assertEqual(result["options"]["repos"], [("myorg", "myrepo")])

    def test_invalid_surface_access_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "repos": ["owner/repo"], "git": {"access": "write"}},
                "ctx",
                _fail,
            )
        self.assertIn("git.access must be one of", str(caught.exception))

    def test_top_level_access_is_rejected_for_github(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "github", "repos": ["owner/repo"], "access": "read"},
                "ctx",
                _fail,
            )
        self.assertIn("access is not supported", str(caught.exception))

    def test_top_level_auth_is_rejected_for_github(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "auth": {"secret": "github-token"},
                },
                "ctx",
                _fail,
            )
        self.assertIn("auth is not supported", str(caught.exception))

    def test_api_auth_is_rejected_until_rest_auth_exists(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "api": {"access": "read", "auth": {"secret": "github-token"}},
                },
                "ctx",
                _fail,
            )
        self.assertIn("api.auth is not supported yet", str(caught.exception))

    def test_git_auth_requires_access(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "git": {"auth": {"secret": "github-token"}},
                },
                "ctx",
                _fail,
            )
        self.assertIn("git must contain 'access'", str(caught.exception))

    def test_git_readwrite_requires_auth(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "git": {"access": "readwrite"},
                },
                "ctx",
                _fail,
            )
        self.assertIn("git.auth is required", str(caught.exception))

    def test_git_auth_rejects_invalid_secret_ids(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "git": {
                        "access": "read",
                        "auth": {"secret": "../github-token"},
                    },
                },
                "ctx",
                _fail,
            )
        self.assertIn("must match [A-Za-z0-9._-]+", str(caught.exception))

    def test_git_auth_normalizes_to_canonical_transform_metadata(self):
        result = self.catalog.normalize_service_entry(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "git": {
                    "access": "read",
                    "auth": {"secret": "github-token"},
                },
            },
            "ctx",
            _fail,
        )

        git = result["options"]["surface_configs"]["git"]
        self.assertEqual(git["auth"], {"secret": "github-token"})
        self.assertEqual(git["transform"], expected_github_auth_transform())

    def test_readonly_must_be_boolean(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "claude", "readonly": "yes"},
                "ctx",
                _fail,
            )
        self.assertIn("readonly must be a boolean", str(caught.exception))

    def test_merge_mode_replace_is_accepted(self):
        result = self.catalog.normalize_service_entry(
            {"name": "claude", "merge_mode": "replace"},
            "ctx",
            _fail,
        )
        self.assertEqual(result["merge_mode"], "replace")

    def test_merge_mode_other_values_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {"name": "claude", "merge_mode": "extend"},
                "ctx",
                _fail,
            )
        self.assertIn("merge_mode must be 'replace'", str(caught.exception))

    def test_non_mapping_entry_is_rejected(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(123, "ctx", _fail)
        self.assertIn("must be either a string service name", str(caught.exception))


class ServiceCatalogExpansionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_service_catalog_module()

    def expand(self, entry):
        return self.catalog.expand_service_entry(entry, "ctx", _fail)

    def test_plain_string_github_emits_default_catch_all_hosts(self):
        expansion = self.expand("github")

        self.assertEqual(expansion["name"], "github")
        self.assertIsNone(expansion["merge_mode"])
        hosts = [record["host"] for record in expansion["records"]]
        self.assertEqual(
            hosts,
            [
                "github.com",
                "*.github.com",
                "githubusercontent.com",
                "*.githubusercontent.com",
            ],
        )
        for record in expansion["records"]:
            self.assertEqual(
                record["rules"],
                [{"schemes": ["http", "https"]}],
            )

    def test_simple_service_readonly_narrows_to_get_head(self):
        expansion = self.expand({"name": "claude", "readonly": True})

        for record in expansion["records"]:
            self.assertEqual(
                record["rules"],
                [{"schemes": ["http", "https"], "methods": ["GET", "HEAD"]}],
            )

    def test_pi_service_emits_no_records(self):
        expansion = self.expand("pi")
        self.assertEqual(expansion["records"], [])

    def test_github_repo_scoped_readwrite_emits_full_api_and_git_rules(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "readwrite"},
                "git": {
                    "access": "readwrite",
                    "auth": {"secret": "github-token"},
                },
            }
        )

        records_by_host = {record["host"]: record for record in expansion["records"]}
        self.assertEqual(set(records_by_host), {"api.github.com", "github.com"})

        api_rules = records_by_host["api.github.com"]["rules"]
        self.assertEqual(
            api_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "path": {"exact": "/repos/owner/repo"},
                },
                {
                    "schemes": ["http", "https"],
                    "path": {"prefix": "/repos/owner/repo/"},
                },
            ],
        )

        expected_transform = expected_github_auth_transform()
        git_rules = records_by_host["github.com"]["rules"]
        self.assertEqual(
            git_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/owner/repo.git/info/refs"},
                    "query": {"exact": {"service": ["git-upload-pack"]}},
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-upload-pack"},
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/owner/repo.git/info/refs"},
                    "query": {"exact": {"service": ["git-receive-pack"]}},
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-receive-pack"},
                    "transform": expected_transform,
                },
            ],
        )

    def test_github_repo_scoped_read_emits_only_upload_pack_paths(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "read"},
                "git": {"access": "read"},
            }
        )

        records_by_host = {record["host"]: record for record in expansion["records"]}

        api_rules = records_by_host["api.github.com"]["rules"]
        for rule in api_rules:
            self.assertEqual(rule["methods"], ["GET", "HEAD"])

        git_rules = records_by_host["github.com"]["rules"]
        self.assertEqual(
            git_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/owner/repo.git/info/refs"},
                    "query": {"exact": {"service": ["git-upload-pack"]}},
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-upload-pack"},
                },
            ],
        )

        for rule in git_rules:
            self.assertNotIn(
                "/git-receive-pack", rule["path"].get("exact", "")
            )

    def test_github_api_only_surface_omits_git_host(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "readwrite"},
            }
        )
        hosts = [record["host"] for record in expansion["records"]]
        self.assertEqual(hosts, ["api.github.com"])

    def test_github_git_only_surface_omits_api_host(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "git": {"access": "read"},
            }
        )
        hosts = [record["host"] for record in expansion["records"]]
        self.assertEqual(hosts, ["github.com"])

    def test_multi_repo_expansion_is_deterministic_and_includes_each_repo(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/a", "owner/b"],
                "api": {"access": "readwrite"},
            }
        )
        api_rules = expansion["records"][0]["rules"]
        self.assertEqual(
            [rule["path"] for rule in api_rules],
            [
                {"exact": "/repos/owner/a"},
                {"prefix": "/repos/owner/a/"},
                {"exact": "/repos/owner/b"},
                {"prefix": "/repos/owner/b/"},
            ],
        )

    def test_duplicate_repos_are_collapsed(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["Owner/A", "owner/a"],
                "api": {"access": "readwrite"},
            }
        )
        api_rules = expansion["records"][0]["rules"]
        self.assertEqual(
            api_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "path": {"exact": "/repos/owner/a"},
                },
                {
                    "schemes": ["http", "https"],
                    "path": {"prefix": "/repos/owner/a/"},
                },
            ],
        )

    def test_merge_mode_replace_is_preserved_in_expansion(self):
        expansion = self.expand(
            {"name": "github", "merge_mode": "replace"},
        )
        self.assertEqual(expansion["merge_mode"], "replace")


if __name__ == "__main__":
    unittest.main()
