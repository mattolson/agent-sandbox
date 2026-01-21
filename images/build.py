#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent

# Defaults (env overrides allowed)
TZ = os.environ.get("TZ", "America/Los_Angeles")
YQ_VERSION = os.environ.get("YQ_VERSION", "v4.44.1")
PYTHON_VERSION = os.environ.get("PYTHON_VERSION", "3.13.11")
UV_VERSION = os.environ.get("UV_VERSION", "0.9.26")
GIT_DELTA_VERSION = os.environ.get("GIT_DELTA_VERSION", "0.18.2")
ZSH_IN_DOCKER_VERSION = os.environ.get("ZSH_IN_DOCKER_VERSION", "1.2.0")
CLAUDE_CODE_VERSION = os.environ.get("CLAUDE_CODE_VERSION", "latest")


def run_docker_build(tag: str, context: Path, build_args: dict[str, str]) -> None:
    print(f"Building {tag}...")
    for key, value in build_args.items():
        print(f"  {key}={value}")

    cmd = [
        "docker",
        "build",
        *(
            arg
            for kv in build_args.items()
            for arg in ("--build-arg", f"{kv[0]}={kv[1]}")
        ),
        "-t",
        tag,
        str(context),
    ]
    subprocess.check_call(cmd)


def build_base() -> None:
    build_args = {
        "TZ": TZ,
        "YQ_VERSION": YQ_VERSION,
        "GIT_DELTA_VERSION": GIT_DELTA_VERSION,
        "ZSH_IN_DOCKER_VERSION": ZSH_IN_DOCKER_VERSION,
    }
    run_docker_build("agent-sandbox-base:local", SCRIPT_DIR / "base", build_args)


def build_claude() -> None:
    build_args = {
        "BASE_IMAGE": "agent-sandbox-base:local",
        "CLAUDE_CODE_VERSION": CLAUDE_CODE_VERSION,
        "PYTHON_VERSION": PYTHON_VERSION,
        "UV_VERSION": UV_VERSION,
    }
    run_docker_build(
        "agent-sandbox-claude:local", SCRIPT_DIR / "agents" / "claude", build_args
    )


def print_usage() -> None:
    prog = Path(sys.argv[0]).name
    usage = f"""Usage: {prog} [base|claude|all]

Environment variables:
  TZ                       Timezone (default: {TZ})
  YQ_VERSION               yq version (default: {YQ_VERSION})
  PYTHON_VERSION           Python version (default: {PYTHON_VERSION})
  UV_VERSION               uv version (default: {UV_VERSION})
  GIT_DELTA_VERSION        git-delta version (default: {GIT_DELTA_VERSION})
  ZSH_IN_DOCKER_VERSION    zsh-in-docker version (default: {ZSH_IN_DOCKER_VERSION})
  CLAUDE_CODE_VERSION      Claude Code version (default: {CLAUDE_CODE_VERSION})
"""
    print(usage)


def main() -> None:
    target = sys.argv[1] if len(sys.argv) > 1 else "all"

    if target == "base":
        build_base()
    elif target == "claude":
        build_claude()
    elif target == "all":
        build_base()
        build_claude()
    else:
        print_usage()
        sys.exit(1)

    print("Done.")


if __name__ == "__main__":
    main()
