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


def expected_github_auth_transform(secret="github-token", on_existing_header="fail"):
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
            "on_existing_header": on_existing_header,
        },
    }


def expected_github_api_auth_transform(secret="github-token", on_existing_header="fail"):
    return {
        "request": {
            "headers": {
                "Authorization": {
                    "secret": secret,
                    "transform": {"type": "bearer"},
                },
            },
            "on_existing_header": on_existing_header,
        },
    }


def expected_github_git_askpass_hint(secret="github-token"):
    return {
        "service": "github",
        "surface": "git",
        "kind": "git-askpass",
        "host": "github.com",
        "username": "x-access-token",
        "fake_password": "agentbox-proxy-managed",
        "secrets": [secret],
    }


def _api_rule(methods, path):
    return {
        "schemes": ["http", "https"],
        "methods": methods,
        "path": path,
        "path_case_insensitive": True,
    }


def expected_api_read_rules(owner, repo):
    base = f"/repos/{owner}/{repo}"
    return [
        _api_rule(["GET", "HEAD"], {"exact": base}),
        _api_rule(["GET", "HEAD"], {"prefix": base + "/"}),
    ]


def expected_api_readwrite_rules(owner, repo):
    base = f"/repos/{owner}/{repo}"
    return expected_api_read_rules(owner, repo) + [
        _api_rule(["POST"], {"exact": base + "/issues"}),
        _api_rule(["POST", "PATCH"], {"prefix": base + "/issues/"}),
        _api_rule(["POST"], {"exact": base + "/pulls"}),
        _api_rule(["POST", "PATCH"], {"prefix": base + "/pulls/"}),
    ]


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

    def test_api_auth_normalizes_to_a_bearer_transform(self):
        normalized = self.catalog.normalize_service_entry(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "read", "auth": {"secret": "github-token"}},
            },
            "ctx",
            _fail,
        )
        api = normalized["options"]["surface_configs"]["api"]
        self.assertEqual(api["auth"], {"secret": "github-token"})
        self.assertEqual(api["transform"], expected_github_api_auth_transform())
        self.assertNotIn("credential_shim_hints", api)

    def test_api_auth_is_optional_for_readwrite(self):
        # Unlike git push, an unauthenticated readwrite api surface is a valid
        # (if discouraged) shape: the client may carry its own token.
        normalized = self.catalog.normalize_service_entry(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "readwrite"},
            },
            "ctx",
            _fail,
        )
        self.assertNotIn("transform", normalized["options"]["surface_configs"]["api"])

    def test_api_client_shim_is_rejected_until_an_api_shim_kind_exists(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "api": {
                        "access": "read",
                        "auth": {
                            "secret": "github-token",
                            "client_shim": {"kind": "git-askpass"},
                        },
                    },
                },
                "ctx",
                _fail,
            )
        self.assertIn("client_shim is not supported on the api surface", str(caught.exception))

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

    def test_git_auth_client_shim_normalizes_to_replace_transform_and_hint(self):
        result = self.catalog.normalize_service_entry(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "git": {
                    "access": "readwrite",
                    "auth": {
                        "secret": "github-token",
                        "client_shim": {"kind": "git-askpass"},
                    },
                },
            },
            "ctx",
            _fail,
        )

        git = result["options"]["surface_configs"]["git"]
        self.assertEqual(
            git["auth"],
            {
                "secret": "github-token",
                "client_shim": {"kind": "git-askpass"},
            },
        )
        self.assertEqual(
            git["transform"],
            expected_github_auth_transform(on_existing_header="replace"),
        )
        self.assertEqual(
            git["credential_shim_hints"],
            [expected_github_git_askpass_hint()],
        )

    def test_git_auth_client_shim_rejects_unknown_kind(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "git": {
                        "access": "read",
                        "auth": {
                            "secret": "github-token",
                            "client_shim": {"kind": "env-bearer"},
                        },
                    },
                },
                "ctx",
                _fail,
            )
        self.assertIn("client_shim.kind must be one of", str(caught.exception))

    def test_git_auth_client_shim_rejects_unknown_keys(self):
        with self.assertRaises(_CatalogFailure) as caught:
            self.catalog.normalize_service_entry(
                {
                    "name": "github",
                    "repos": ["owner/repo"],
                    "git": {
                        "access": "read",
                        "auth": {
                            "secret": "github-token",
                            "client_shim": {
                                "kind": "git-askpass",
                                "env": "GITHUB_TOKEN",
                            },
                        },
                    },
                },
                "ctx",
                _fail,
            )
        self.assertIn("client_shim contains unsupported keys", str(caught.exception))

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

    def test_github_default_catch_all_rules_are_not_case_insensitive(self):
        # Host-wide catch-all rules have no path, so the case-insensitive flag
        # must not leak onto them; it only applies to repo-scoped path rules.
        expansion = self.expand("github")
        for record in expansion["records"]:
            for rule in record["rules"]:
                self.assertNotIn("path_case_insensitive", rule)

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
        self.assertEqual(api_rules, expected_api_readwrite_rules("owner", "repo"))

        expected_transform = expected_github_auth_transform()
        git_rules = records_by_host["github.com"]["rules"]
        self.assertEqual(
            git_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/owner/repo.git/info/refs"},
                    "path_case_insensitive": True,
                    "query": {"exact": {"service": ["git-upload-pack"]}},
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-upload-pack"},
                    "path_case_insensitive": True,
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/owner/repo.git/info/refs"},
                    "path_case_insensitive": True,
                    "query": {"exact": {"service": ["git-receive-pack"]}},
                    "transform": expected_transform,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-receive-pack"},
                    "path_case_insensitive": True,
                    "transform": expected_transform,
                },
            ],
        )
        self.assertEqual(expansion["credential_shim"], [])

    def test_github_git_client_shim_expansion_emits_credential_hint(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "git": {
                    "access": "readwrite",
                    "auth": {
                        "secret": "github-token",
                        "client_shim": {"kind": "git-askpass"},
                    },
                },
            }
        )

        self.assertEqual(
            expansion["credential_shim"],
            [expected_github_git_askpass_hint()],
        )
        git_rules = expansion["records"][0]["rules"]
        self.assertTrue(
            all(
                rule["transform"] == expected_github_auth_transform(
                    on_existing_header="replace"
                )
                for rule in git_rules
            )
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
                    "path_case_insensitive": True,
                    "query": {"exact": {"service": ["git-upload-pack"]}},
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["POST"],
                    "path": {"exact": "/owner/repo.git/git-upload-pack"},
                    "path_case_insensitive": True,
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

    def test_github_api_readwrite_is_an_enumerated_write_allowlist(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "readwrite"},
            }
        )
        api_rules = expansion["records"][0]["rules"]
        self.assertEqual(api_rules, expected_api_readwrite_rules("owner", "repo"))

        # Every write rule names its methods; nothing under readwrite is a
        # method-less catch-all, and PUT/DELETE never appear.
        for rule in api_rules:
            self.assertIn("methods", rule)
            self.assertNotIn("PUT", rule["methods"])
            self.assertNotIn("DELETE", rule["methods"])

        # Write rules exist only for the issues and pulls families.
        write_paths = sorted(
            (rule["path"].get("exact") or rule["path"].get("prefix"))
            for rule in api_rules
            if set(rule["methods"]) & {"POST", "PATCH"}
        )
        self.assertEqual(
            write_paths,
            [
                "/repos/owner/repo/issues",
                "/repos/owner/repo/issues/",
                "/repos/owner/repo/pulls",
                "/repos/owner/repo/pulls/",
            ],
        )

    def test_github_api_auth_applies_bearer_transform_to_every_api_rule(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "readwrite", "auth": {"secret": "github-token"}},
                "git": {"access": "read"},
            }
        )
        records_by_host = {record["host"]: record for record in expansion["records"]}
        api_rules = records_by_host["api.github.com"]["rules"]
        self.assertEqual(len(api_rules), 6)
        expected = expected_github_api_auth_transform()
        self.assertTrue(all(rule["transform"] == expected for rule in api_rules))
        # git had no auth, so its rules carry no transform.
        for rule in records_by_host["github.com"]["rules"]:
            self.assertNotIn("transform", rule)
        self.assertEqual(expansion["credential_shim"], [])

    def test_github_api_read_has_no_write_rules(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/repo"],
                "api": {"access": "read"},
            }
        )
        api_rules = expansion["records"][0]["rules"]
        self.assertEqual(len(api_rules), 2)
        for rule in api_rules:
            self.assertEqual(rule["methods"], ["GET", "HEAD"])

    def test_multi_repo_expansion_is_deterministic_and_includes_each_repo(self):
        expansion = self.expand(
            {
                "name": "github",
                "repos": ["owner/a", "owner/b"],
                "api": {"access": "read"},
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
                "api": {"access": "read"},
            }
        )
        api_rules = expansion["records"][0]["rules"]
        self.assertEqual(
            api_rules,
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/repos/owner/a"},
                    "path_case_insensitive": True,
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"prefix": "/repos/owner/a/"},
                    "path_case_insensitive": True,
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
