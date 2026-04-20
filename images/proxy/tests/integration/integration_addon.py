"""Wrapper addon for integration tests.

Mitmdump loads this file with `-s`. It imports the real enforcer addon from
`images/proxy/addons/enforcer.py` but redirects the hard-coded
`RENDER_POLICY_PATH` at `AGENTBOX_RENDER_POLICY_PATH` so reload tests can run
without installing the render-policy script at `/usr/local/bin`.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    ADDON_DIR = Path(os.environ["AGENTBOX_ADDON_DIR"])
except KeyError as error:
    raise RuntimeError(
        "AGENTBOX_ADDON_DIR env var is required; point it at images/proxy/addons"
    ) from error
if str(ADDON_DIR) not in sys.path:
    sys.path.insert(0, str(ADDON_DIR))

import enforcer  # noqa: E402

render_policy_path = os.environ.get("AGENTBOX_RENDER_POLICY_PATH")
if render_policy_path:
    enforcer.RENDER_POLICY_PATH = Path(render_policy_path)

addons = enforcer.addons
