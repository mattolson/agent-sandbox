import importlib.util
import os
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
POLICY_MATCHER_PATH = REPO_ROOT / "images" / "proxy" / "addons" / "policy_matcher.py"
RENDER_POLICY_PATH = REPO_ROOT / "images" / "proxy" / "render-policy"


def load_policy_matcher_module():
    loader = SourceFileLoader("policy_matcher_module", str(POLICY_MATCHER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def load_render_policy_module():
    loader = SourceFileLoader("render_policy_module", str(RENDER_POLICY_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class PolicyMatcherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy_matcher = load_policy_matcher_module()

    def matcher_from_domains(self, domains):
        return self.policy_matcher.PolicyMatcher.from_policy_data({"domains": domains})

    def test_selects_exact_host_over_matching_wildcard(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "*.github.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"prefix": "/wild"},
                        }
                    ],
                },
                {
                    "host": "api.github.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"prefix": "/exact"},
                        }
                    ],
                },
            ]
        )

        blocked = matcher.evaluate_request(
            "api.github.com",
            "https",
            "GET",
            "/wild/resource",
        )
        allowed = matcher.evaluate_request(
            "api.github.com",
            "https",
            "GET",
            "/exact/resource",
        )

        self.assertEqual(blocked.action, "blocked")
        self.assertEqual(blocked.reason, "no_rule_matched")
        self.assertEqual(blocked.matched_host, "api.github.com")
        self.assertEqual(allowed.action, "allowed")
        self.assertEqual(allowed.matched_host, "api.github.com")

    def test_selects_longest_matching_wildcard_suffix(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "*.github.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"prefix": "/short"},
                        }
                    ],
                },
                {
                    "host": "*.api.github.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"prefix": "/long"},
                        }
                    ],
                },
            ]
        )

        decision = matcher.evaluate_request(
            "v3.api.github.com",
            "https",
            "GET",
            "/long/value",
        )

        self.assertEqual(decision.action, "allowed")
        self.assertEqual(decision.matched_host, "*.api.github.com")

    def test_connect_blocks_when_no_host_record_matches(self):
        matcher = self.matcher_from_domains(["api.openai.com"])

        decision = matcher.evaluate_connect("blocked.example")

        self.assertEqual(decision.action, "blocked")
        self.assertEqual(decision.reason, "host_not_allowed")

    def test_connect_blocks_when_https_is_not_permitted(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["http"],
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_connect("api.openai.com")

        self.assertEqual(decision.action, "blocked")
        self.assertEqual(decision.reason, "https_not_permitted")
        self.assertEqual(decision.matched_host, "api.openai.com")

    def test_connect_allows_fast_path_for_unconditional_https_rule(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_connect("api.openai.com")

        self.assertEqual(decision.action, "allowed")
        self.assertEqual(decision.reason, "connect_fast_path")

    def test_connect_defers_to_request_for_rule_bearing_https_host(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["GET"],
                            "path": {"prefix": "/v1/models"},
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_connect("api.openai.com")

        self.assertEqual(decision.action, "allowed")
        self.assertEqual(decision.reason, "connect_inspect_request")

    def test_request_matches_methods_case_insensitively_after_normalization(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "methods": ["post"],
                            "path": {"exact": "/v1/responses"},
                        }
                    ],
                }
            ]
        )

        allowed = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "post",
            "/v1/responses",
        )
        blocked = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/responses",
        )

        self.assertEqual(allowed.action, "allowed")
        self.assertEqual(blocked.action, "blocked")
        self.assertEqual(blocked.reason, "no_rule_matched")

    def test_request_matches_exact_and_prefix_paths_without_query_string(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"exact": "/v1/models"},
                        },
                        {
                            "schemes": ["https"],
                            "path": {"prefix": "/v1/files/"},
                        },
                    ],
                }
            ]
        )

        exact = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models?limit=10",
        )
        prefix = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/files/abc?download=1",
        )

        self.assertEqual(exact.action, "allowed")
        self.assertEqual(exact.path, "/v1/models")
        self.assertEqual(prefix.action, "allowed")
        self.assertEqual(prefix.path, "/v1/files/abc")

    def test_request_matches_exact_query_independent_of_pair_order(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"exact": "/v1/models"},
                            "query": {
                                "exact": {
                                    "a": ["1"],
                                    "b": ["2"],
                                }
                            },
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models?b=2&a=1",
        )

        self.assertEqual(decision.action, "allowed")

    def test_request_matches_repeated_query_values_with_order_independence(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"exact": "/v1/models"},
                            "query": {
                                "exact": {
                                    "tag": ["b", "a"],
                                }
                            },
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models?tag=a&tag=b",
        )

        self.assertEqual(decision.action, "allowed")

    def test_request_uses_same_rule_semantics_for_http_and_https(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["http", "https"],
                            "methods": ["GET"],
                            "path": {"exact": "/v1/models"},
                        }
                    ],
                }
            ]
        )

        http_decision = matcher.evaluate_request(
            "api.openai.com",
            "http",
            "GET",
            "/v1/models",
        )
        https_decision = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models",
        )

        self.assertEqual(http_decision.action, "allowed")
        self.assertEqual(https_decision.action, "allowed")

    def test_request_matches_explicit_empty_query_constraint(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"exact": "/v1/models"},
                            "query": {"exact": {}},
                        }
                    ],
                }
            ]
        )

        allowed = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models",
        )
        blocked = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models?limit=10",
        )

        self.assertEqual(allowed.action, "allowed")
        self.assertEqual(blocked.action, "blocked")
        self.assertEqual(blocked.reason, "no_rule_matched")

    def test_request_exact_query_rejects_extra_params(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["https"],
                            "path": {"exact": "/v1/models"},
                            "query": {"exact": {"limit": ["10"]}},
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/v1/models?limit=10&extra=1",
        )

        self.assertEqual(decision.action, "blocked")
        self.assertEqual(decision.reason, "no_rule_matched")

    def test_request_blocks_with_scheme_not_permitted_when_host_matches_but_scheme_does_not(self):
        matcher = self.matcher_from_domains(
            [
                {
                    "host": "api.openai.com",
                    "rules": [
                        {
                            "schemes": ["http"],
                        }
                    ],
                }
            ]
        )

        decision = matcher.evaluate_request(
            "api.openai.com",
            "https",
            "GET",
            "/",
        )

        self.assertEqual(decision.action, "blocked")
        self.assertEqual(decision.reason, "scheme_not_permitted")


class PolicyMatcherGithubServiceIntegrationTests(unittest.TestCase):
    """Prove the generic matcher enforces GitHub service expansions end-to-end.

    This test renders a policy through the real render-policy pipeline and loads
    the output into the generic matcher. No GitHub-specific matcher branches
    should exist, so the test's contract is that semantic service expansion at
    render time is sufficient for runtime enforcement.
    """

    @classmethod
    def setUpClass(cls):
        cls.policy_matcher = load_policy_matcher_module()
        cls.render_policy = load_render_policy_module()

    def _matcher_from_rendered(self, authored_yaml):
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "policy.yaml"
            path.write_text(authored_yaml, encoding="utf-8")
            with mock.patch.dict(
                os.environ,
                {"AGENTBOX_POLICY_SOURCE_PATH": str(path)},
                clear=False,
            ):
                rendered = self.render_policy.render_single_policy()
        return self.policy_matcher.PolicyMatcher.from_policy_data(rendered)

    def test_readonly_github_repo_scoped_policy_enforces_clone_and_blocks_push(self):
        matcher = self._matcher_from_rendered(
            """
services:
  - name: github
    readonly: true
    repos:
      - owner/repo
    surfaces:
      - api
      - git
"""
        )

        in_repo = matcher.evaluate_request(
            "api.github.com",
            "https",
            "GET",
            "/repos/owner/repo/issues",
        )
        self.assertEqual(in_repo.action, "allowed")
        self.assertEqual(in_repo.matched_host, "api.github.com")

        other_repo = matcher.evaluate_request(
            "api.github.com",
            "https",
            "GET",
            "/repos/other/repo",
        )
        self.assertEqual(other_repo.action, "blocked")
        self.assertEqual(other_repo.reason, "no_rule_matched")

        write_attempt = matcher.evaluate_request(
            "api.github.com",
            "https",
            "POST",
            "/repos/owner/repo/issues",
        )
        self.assertEqual(write_attempt.action, "blocked")
        self.assertEqual(write_attempt.reason, "no_rule_matched")

        fetch_discovery = matcher.evaluate_request(
            "github.com",
            "https",
            "GET",
            "/owner/repo.git/info/refs?service=git-upload-pack",
        )
        self.assertEqual(fetch_discovery.action, "allowed")

        fetch_data = matcher.evaluate_request(
            "github.com",
            "https",
            "POST",
            "/owner/repo.git/git-upload-pack",
        )
        self.assertEqual(fetch_data.action, "allowed")

        push_discovery = matcher.evaluate_request(
            "github.com",
            "https",
            "GET",
            "/owner/repo.git/info/refs?service=git-receive-pack",
        )
        self.assertEqual(push_discovery.action, "blocked")
        self.assertEqual(push_discovery.reason, "no_rule_matched")

        push_data = matcher.evaluate_request(
            "github.com",
            "https",
            "POST",
            "/owner/repo.git/git-receive-pack",
        )
        self.assertEqual(push_data.action, "blocked")
        self.assertEqual(push_data.reason, "no_rule_matched")


if __name__ == "__main__":
    unittest.main()
