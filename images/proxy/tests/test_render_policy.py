import importlib.util
import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr
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
        stderr = io.StringIO()
        with redirect_stderr(stderr):
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

        self.assertIn("both 'scheme' and 'schemes'", stderr.getvalue())
        self.assertIn("both 'method' and 'methods'", stderr.getvalue())
        self.assertEqual(
            rendered["domains"][0]["rules"][0],
            {
                "schemes": ["http", "https"],
                "methods": ["GET", "POST"],
                "path": {"exact": "/meta"},
            },
        )

    def test_empty_rule_is_rejected(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                self.render_single(
                    """
domains:
  - host: api.github.com
    rules:
      - {}
"""
                )

        self.assertIn("must not be empty", stderr.getvalue())

    def test_unknown_service_is_rejected(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                self.render_single(
                    """
services:
  - not-a-service
"""
                )

        self.assertIn("unknown service", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
