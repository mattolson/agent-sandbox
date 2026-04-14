# Python Stack

See [Language stacks](./README.md) for the shared stack workflow.

The Python stack installs these system packages:

- `python3`
- `python3-dev`
- `python3-pip`
- `python3-setuptools`
- `python3-venv`
- `python3-wheel`
- `build-essential`
- `pkg-config`
- `libffi-dev`
- `libssl-dev`

It also configures these paths for the `dev` user:

- `PATH=$HOME/.local/bin:/usr/local/bin:$PATH`
- `PIP_CACHE_DIR=$HOME/.cache/pip`

Use the system interpreter only to create project environments. For normal work, pick one of these workflows.

## Default-Deny Local Workflow

In the default sandbox policy, Debian's Python packaging behavior matters:

- `pip install ...` and `pip install --user ...` outside a virtualenv are blocked by PEP 668 (`externally-managed-environment`)
- Fresh `python -m venv` environments include `pip` and `setuptools`, but not `wheel`
- `python3-wheel` is installed system-wide by this stack, but a standard virtualenv does not see it unless you use `--system-site-packages`
- `python -m venv --upgrade-deps` reaches PyPI, so it is not useful under the default-deny policy

If you need to work on a checked-in local package without allowing a package registry, create the venv with system site
packages so Debian's packaged build tooling remains visible, then disable build isolation for local installs:

```bash
python -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --no-build-isolation -e .
```

This is less isolated than a normal virtualenv because Debian-packaged modules remain visible inside the environment.
If you want a cleaner virtualenv, allow a private mirror or explicit package registry access and use the standard
`python -m venv .venv` workflow instead.

## Registry-Enabled Workflow

Once a private mirror or package registry is allowed by policy, use a standard project-local virtualenv:

```bash
python -m venv .venv
. .venv/bin/activate
pip install wheel  # if your project needs it
```

Do not rely on `pip install --user`. Debian marks the system interpreter as externally managed, so those installs fail
unless you opt into `--break-system-packages`, which this stack does not recommend.

For a persistent local Python dev environment, add a pip cache mount to `.agent-sandbox/compose/user.override.yml`:

```yaml
services:
  agent:
    volumes:
      - pip-cache:/home/dev/.cache/pip

volumes:
  pip-cache:
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

Commands like `pip install ...` that fetch from a registry will only work after you allow that registry.
