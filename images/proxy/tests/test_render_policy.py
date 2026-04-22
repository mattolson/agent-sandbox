import importlib.util
import os
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
RENDER_POLICY_PATH = REPO_ROOT / "images" / "proxy" / "render-policy"


def load_render_policy_module():
    loader = SourceFileLoader("render_policy_module", str(RENDER_POLICY_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class RenderPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.render_policy = load_render_policy_module()

    def render_single(self, policy_text):
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "policy.yaml"
            path.write_text(policy_text, encoding="utf-8")
            with mock.patch.dict(
                os.environ,
                {"AGENTBOX_POLICY_SOURCE_PATH": str(path)},
                clear=False,
            ):
                return self.render_policy.render_single_policy()

    def render_layered(self, active_agent, shared=None, agent=None, devcontainer=None):
        with tempfile.TemporaryDirectory() as tempdir:
            tempdir_path = Path(tempdir)
            shared_path = tempdir_path / "shared.yaml"
            agent_path = tempdir_path / "agent.yaml"
            devcontainer_path = tempdir_path / "devcontainer.yaml"

            if shared is not None:
                shared_path.write_text(shared, encoding="utf-8")
            if agent is not None:
                agent_path.write_text(agent, encoding="utf-8")
            if devcontainer is not None:
                devcontainer_path.write_text(devcontainer, encoding="utf-8")

            env = {
                "AGENTBOX_SHARED_POLICY_PATH": str(shared_path),
                "AGENTBOX_AGENT_POLICY_PATH": str(agent_path),
                "AGENTBOX_DEVCONTAINER_POLICY_PATH": str(devcontainer_path),
            }
            with mock.patch.dict(os.environ, env, clear=False):
                return self.render_policy.render_layered_policy(active_agent)

    def test_single_file_legacy_inputs_render_to_canonical_host_records(self):
        rendered = self.render_single(
            """
services:
  - github
domains:
  - api.openai.com
  - "*.example.com"
"""
        )

        self.assertNotIn("services", rendered)
        records = {record["host"]: record for record in rendered["domains"]}

        self.assertIn("github.com", records)
        self.assertIn("*.github.com", records)
        self.assertIn("githubusercontent.com", records)
        self.assertIn("*.githubusercontent.com", records)
        self.assertIn("api.openai.com", records)
        self.assertIn("*.example.com", records)

        for host in (
            "github.com",
            "*.github.com",
            "githubusercontent.com",
            "*.githubusercontent.com",
            "api.openai.com",
            "*.example.com",
        ):
            self.assertEqual(
                records[host]["rules"],
                [{"schemes": ["http", "https"]}],
            )

    def test_layer_order_is_shared_then_agent_then_devcontainer(self):
        rendered = self.render_layered(
            "pi",
            shared="""
domains:
  - host: api.github.com
    rules:
      - path:
          exact: /shared
""",
            agent="""
domains:
  - host: api.github.com
    rules:
      - path:
          exact: /agent
""",
            devcontainer="""
domains:
  - host: api.github.com
    rules:
      - path:
          exact: /dev
""",
        )

        record = rendered["domains"][0]
        self.assertEqual(record["host"], "api.github.com")
        self.assertEqual(
            record["rules"],
            [
                {"schemes": ["http", "https"], "path": {"exact": "/shared"}},
                {"schemes": ["http", "https"], "path": {"exact": "/agent"}},
                {"schemes": ["http", "https"], "path": {"exact": "/dev"}},
            ],
        )

    def test_same_host_rules_merge_additively_and_dedupe(self):
        rendered = self.render_layered(
            "pi",
            shared="""
domains:
  - host: api.github.com
    rules:
      - method: get
        path:
          prefix: /repos/example/
""",
            agent="""
domains:
  - host: api.github.com
    rules:
      - methods: [GET]
        path:
          prefix: /repos/example/
      - scheme: https
        methods: [post]
        query:
          exact:
            ref: docs
""",
        )

        self.assertEqual(
            rendered["domains"],
            [
                {
                    "host": "api.github.com",
                    "rules": [
                        {
                            "schemes": ["http", "https"],
                            "methods": ["GET"],
                            "path": {"prefix": "/repos/example/"},
                        },
                        {
                            "schemes": ["https"],
                            "methods": ["POST"],
                            "query": {"exact": {"ref": ["docs"]}},
                        },
                    ],
                }
            ],
        )

    def test_merge_mode_replace_can_override_service_expansion(self):
        rendered = self.render_layered(
            "codex",
            agent="""
domains:
  - host: "*.openai.com"
    merge_mode: replace
    rules:
      - scheme: https
        method: get
        path:
          exact: /v1/models
""",
        )

        records = {record["host"]: record for record in rendered["domains"]}
        self.assertEqual(
            records["*.openai.com"]["rules"],
            [
                {
                    "schemes": ["https"],
                    "methods": ["GET"],
                    "path": {"exact": "/v1/models"},
                }
            ],
        )

    def test_host_records_are_sorted_by_match_specificity(self):
        rendered = self.render_single(
            """
domains:
  - "*.github.com"
  - "*.api.github.com"
  - api.github.com
"""
        )

        self.assertEqual(
            [record["host"] for record in rendered["domains"]],
            ["api.github.com", "*.api.github.com", "*.github.com"],
        )

    def test_scheme_and_method_shorthands_warn_and_normalize(self):
        rendered = self.render_single(
            """
domains:
  - host: api.github.com
    rules:
      - scheme: https
        schemes: [http]
        method: get
        methods: [post]
        path:
          exact: /meta
"""
        )

        warnings = self.render_policy.take_warnings()
        self.assertTrue(any("both 'scheme' and 'schemes'" in w for w in warnings))
        self.assertTrue(any("both 'method' and 'methods'" in w for w in warnings))
        self.assertEqual(
            rendered["domains"][0]["rules"][0],
            {
                "schemes": ["http", "https"],
                "methods": ["GET", "POST"],
                "path": {"exact": "/meta"},
            },
        )

    def test_empty_rule_is_rejected(self):
        with self.assertRaises(self.render_policy.RenderPolicyError) as context:
            self.render_single(
                """
domains:
  - host: api.github.com
    rules:
      - {}
"""
            )

        self.assertIn("must not be empty", str(context.exception))

    def test_unknown_service_is_rejected(self):
        with self.assertRaises(self.render_policy.RenderPolicyError) as context:
            self.render_single(
                """
services:
  - not-a-service
"""
            )

        self.assertIn("unknown service", str(context.exception))

    def test_rich_github_repo_scoped_service_renders_to_repo_paths(self):
        rendered = self.render_single(
            """
services:
  - name: github
    repos:
      - owner/repo
    surfaces:
      - api
      - git
    readonly: true
"""
        )

        records = {record["host"]: record for record in rendered["domains"]}
        self.assertIn("api.github.com", records)
        self.assertIn("github.com", records)

        self.assertEqual(
            records["api.github.com"]["rules"],
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/repos/owner/repo"},
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"prefix": "/repos/owner/repo/"},
                },
            ],
        )

        self.assertEqual(
            records["github.com"]["rules"],
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

    def test_same_name_service_entries_are_additive(self):
        rendered = self.render_single(
            """
services:
  - name: github
    repos:
      - owner/a
    surfaces:
      - api
  - name: github
    repos:
      - owner/b
    surfaces:
      - api
"""
        )

        records = {record["host"]: record for record in rendered["domains"]}
        api_paths = [rule["path"] for rule in records["api.github.com"]["rules"]]
        self.assertEqual(
            api_paths,
            [
                {"exact": "/repos/owner/a"},
                {"prefix": "/repos/owner/a/"},
                {"exact": "/repos/owner/b"},
                {"prefix": "/repos/owner/b/"},
            ],
        )
        # Plain-string github baseline catch-all hosts should not appear when
        # the user authored only rich service entries.
        self.assertNotIn("github.com", records)

    def test_service_merge_mode_replace_discards_baseline_expansion(self):
        rendered = self.render_layered(
            "pi",
            shared="""
services:
  - github
""",
            agent="""
services:
  - name: github
    merge_mode: replace
    repos:
      - owner/repo
    surfaces:
      - api
    readonly: true
""",
        )

        records = {record["host"]: record for record in rendered["domains"]}
        self.assertEqual(set(records), {"api.github.com"})
        self.assertEqual(
            records["api.github.com"]["rules"],
            [
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"exact": "/repos/owner/repo"},
                },
                {
                    "schemes": ["http", "https"],
                    "methods": ["GET", "HEAD"],
                    "path": {"prefix": "/repos/owner/repo/"},
                },
            ],
        )

    def test_service_merge_mode_replace_preserves_unrelated_domain_rules(self):
        rendered = self.render_layered(
            "pi",
            shared="""
services:
  - github
domains:
  - host: github.com
    rules:
      - path:
          exact: /custom
""",
            agent="""
services:
  - name: github
    merge_mode: replace
    repos:
      - owner/repo
    surfaces:
      - api
""",
        )

        records = {record["host"]: record for record in rendered["domains"]}
        self.assertIn("github.com", records)
        self.assertEqual(
            records["github.com"]["rules"],
            [
                {
                    "schemes": ["http", "https"],
                    "path": {"exact": "/custom"},
                }
            ],
        )
        self.assertIn("api.github.com", records)
        self.assertNotIn("*.github.com", records)

    def test_service_merge_mode_replace_preserves_deduped_domain_catch_all(self):
        rendered = self.render_layered(
            "pi",
            shared="""
services:
  - copilot
""",
            agent="""
services:
  - name: copilot
    merge_mode: replace
domains:
  - github.com
""",
            devcontainer="""
services:
  - name: copilot
    merge_mode: replace
    readonly: true
""",
        )

        records = {record["host"]: record for record in rendered["domains"]}
        self.assertIn("github.com", records)
        self.assertIn(
            {"schemes": ["http", "https"]},
            records["github.com"]["rules"],
        )
        self.assertEqual(
            records["collector.github.com"]["rules"],
            [{"schemes": ["http", "https"], "methods": ["GET", "HEAD"]}],
        )

    def test_rich_github_baseline_hosts_emit_catch_all_when_no_repos(self):
        rendered = self.render_single(
            """
services:
  - name: github
"""
        )

        hosts = [record["host"] for record in rendered["domains"]]
        self.assertEqual(
            sorted(hosts),
            sorted(
                [
                    "github.com",
                    "*.github.com",
                    "githubusercontent.com",
                    "*.githubusercontent.com",
                ]
            ),
        )
        for record in rendered["domains"]:
            self.assertEqual(record["rules"], [{"schemes": ["http", "https"]}])


BASELINE_CATCH_ALL_RULE = {"schemes": ["http", "https"]}

BASELINE_AGENT_HOSTS = {
    "claude": ["*.anthropic.com", "*.claude.ai", "*.claude.com"],
    "codex": ["*.openai.com", "chatgpt.com", "*.chatgpt.com"],
    "factory": ["api.factory.ai", "api.workos.com"],
    "gemini": [
        "cloudcode-pa.googleapis.com",
        "generativelanguage.googleapis.com",
        "oauth2.googleapis.com",
    ],
    "opencode": ["opencode.ai", "*.opencode.ai", "models.dev"],
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
}


class BaselinePolicyRegressionTests(unittest.TestCase):
    """Pin each agent baseline to a CONNECT-fast-path IR shape.

    Backward compatibility in m14 means `services: [<agent>]` renders to the
    same host list with a plain catch-all rule as it did before request-aware
    rules landed. These tests make that guarantee explicit so any future
    catalog change has to edit the expected structure.
    """

    @classmethod
    def setUpClass(cls):
        cls.render_policy = load_render_policy_module()

    def render_baseline(self, agent):
        policy_text = f"services:\n  - {agent}\n"
        with tempfile.TemporaryDirectory() as tempdir:
            path = Path(tempdir) / "policy.yaml"
            path.write_text(policy_text, encoding="utf-8")
            with mock.patch.dict(
                os.environ,
                {"AGENTBOX_POLICY_SOURCE_PATH": str(path)},
                clear=False,
            ):
                return self.render_policy.render_single_policy()

    def _assert_baseline(self, agent, expected_hosts):
        rendered = self.render_baseline(agent)
        self.assertNotIn("services", rendered)
        got_hosts = [record["host"] for record in rendered["domains"]]
        self.assertEqual(sorted(got_hosts), sorted(expected_hosts))
        for record in rendered["domains"]:
            self.assertEqual(record["rules"], [BASELINE_CATCH_ALL_RULE])

    def test_claude_baseline(self):
        self._assert_baseline("claude", BASELINE_AGENT_HOSTS["claude"])

    def test_codex_baseline(self):
        self._assert_baseline("codex", BASELINE_AGENT_HOSTS["codex"])

    def test_factory_baseline(self):
        self._assert_baseline("factory", BASELINE_AGENT_HOSTS["factory"])

    def test_gemini_baseline(self):
        self._assert_baseline("gemini", BASELINE_AGENT_HOSTS["gemini"])

    def test_opencode_baseline(self):
        self._assert_baseline("opencode", BASELINE_AGENT_HOSTS["opencode"])

    def test_pi_baseline(self):
        self._assert_baseline("pi", BASELINE_AGENT_HOSTS["pi"])

    def test_copilot_baseline(self):
        self._assert_baseline("copilot", BASELINE_AGENT_HOSTS["copilot"])

    def test_github_default_baseline(self):
        self._assert_baseline(
            "github",
            [
                "github.com",
                "*.github.com",
                "githubusercontent.com",
                "*.githubusercontent.com",
            ],
        )


if __name__ == "__main__":
    unittest.main()
