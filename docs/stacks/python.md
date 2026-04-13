# Python Stack

See [Language stacks](./README.md) for the shared stack workflow.

The Python stack installs these system packages:

- `python3`
- `python3-dev`
- `python3-pip`
- `python3-setuptools`
- `python3-venv`
- `python3-wheel`
- `pipx`
- `build-essential`
- `pkg-config`
- `libffi-dev`
- `libssl-dev`

It also configures these paths for the `dev` user:

- `PATH=$HOME/.local/bin:$HOME/.local/pipx/bin:/usr/local/bin:$PATH`
- `PIP_CACHE_DIR=$HOME/.cache/pip`
- `PIPX_HOME=$HOME/.local/pipx`
- `PIPX_BIN_DIR=$HOME/.local/pipx/bin`

Use the system interpreter only to create project environments. For normal work, create a project-local virtualenv in
your checkout:

```bash
python -m venv .venv
. .venv/bin/activate
```

For standalone Python CLIs outside a project venv, prefer `pipx` over `pip install --user`:

```bash
pipx install ruff
pipx install poetry
```

`pip install --user` still drops scripts into `~/.local/bin`, which is where agent images place tools like `codex`.
That directory should stay reserved for agent binaries and should not be shared as a cross-agent volume.

For a persistent local Python dev environment, add cache and pipx mounts to `.agent-sandbox/compose/user.override.yml`:

```yaml
services:
  agent:
    volumes:
      - pip-cache:/home/dev/.cache/pip
      - pipx-home:/home/dev/.local/pipx

volumes:
  pip-cache:
  pipx-home:
```

Package registry access is intentionally closed by default. That keeps public package download out of the baseline
security posture while still giving you a complete local Python toolchain for checked-in code, local virtualenvs, and
mounted artifacts.

If you need package installs inside the sandbox, prefer allowing a private package mirror or proxy instead of public
PyPI. For example:

```yaml
domains:
  - python-packages.example.com
```

If you explicitly want public PyPI for local development, opt in by adding these domains to your policy:

```yaml
domains:
  - pypi.org
  - files.pythonhosted.org
```

Commands like `pip install ...` and `pipx install ...` that fetch from a registry will only work after you allow that
registry.
