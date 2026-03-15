# Upgrade Legacy Single-File Layouts To The m8 Layered Runtime Model

This guide is for projects that still use the older single-file sandbox layout.

Typical legacy files:

- `.agent-sandbox/docker-compose.yml`
- `.devcontainer/docker-compose.yml`
- `.agent-sandbox/policy-cli-<agent>.yaml`
- `.agent-sandbox/policy-devcontainer-<agent>.yaml`

Current `agentbox` commands no longer operate on those files in place. They expect the layered runtime model under
`.agent-sandbox/compose/` and `.agent-sandbox/policy/`.

## What changed in m8

The old model treated one generated compose file and one generated policy file as live configuration.

The `m8` layout splits ownership explicitly:

- Managed compose layers live under `.agent-sandbox/compose/`
- User-owned compose overrides live under `.agent-sandbox/compose/user.override.yml` and `.agent-sandbox/compose/user.agent.<agent>.override.yml`
- User-owned policy files live under `.agent-sandbox/policy/user.policy.yaml` and `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
- Devcontainer runtime compose and policy files also live under `.agent-sandbox/`
- `.devcontainer/` is now just the IDE-facing shim: `devcontainer.json` plus optional `devcontainer.user.json`

That split is what makes non-destructive `agentbox switch --agent <name>` possible.

## Upgrade flow

1. Rename the legacy generated files so `agentbox` no longer treats them as live configuration.
2. Re-run `agentbox init` for the mode and agent you actually want to use now.
3. Copy your customizations into the new user-owned layered files.
4. If you use devcontainers, rerun `agentbox switch --agent <current-agent>` after editing `devcontainer.user.json` so `devcontainer.json` is regenerated.

## Step 1: Rename legacy generated files

Do not delete them immediately. Rename them first so you keep a reference copy while upgrading.

Examples:

```text
.agent-sandbox/docker-compose.yml -> .agent-sandbox/docker-compose.legacy.yml
.devcontainer/docker-compose.yml -> .devcontainer/docker-compose.legacy.yml
.agent-sandbox/policy-cli-claude.yaml -> .agent-sandbox/policy-cli-claude.legacy.yaml
.agent-sandbox/policy-devcontainer-claude.yaml -> .agent-sandbox/policy-devcontainer-claude.legacy.yaml
```

The important part is that the live filename is gone. `*.legacy.*` is the recommended convention because it keeps the
file type obvious.

## Step 2: Re-run init

CLI example:

```bash
agentbox init --agent claude --mode cli
```

Devcontainer example:

```bash
agentbox init --agent claude --mode devcontainer --ide vscode
```

If you use batch mode already, keep using it:

```bash
agentbox init --batch --agent claude --mode cli --path /path/to/project
```

## Step 3: Move customizations to the new user-owned files

Compose customizations now belong in:

- `.agent-sandbox/compose/user.override.yml`
- `.agent-sandbox/compose/user.agent.<agent>.override.yml`

Policy customizations now belong in:

- `.agent-sandbox/policy/user.policy.yaml`
- `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`

Devcontainer JSON customizations now belong in:

- `.devcontainer/devcontainer.user.json`

Do not copy customizations back into managed files such as:

- `.agent-sandbox/compose/base.yml`
- `.agent-sandbox/compose/agent.<agent>.yml`
- `.agent-sandbox/compose/mode.devcontainer.yml`
- `.agent-sandbox/policy/policy.devcontainer.yaml`
- `.devcontainer/devcontainer.json`

## Step 4: Resync devcontainer.json when needed

If you changed `.devcontainer/devcontainer.user.json`, regenerate the IDE-facing file before reopening the devcontainer:

```bash
agentbox switch --agent <current-agent>
```

That same-agent switch path preserves the layered runtime files and refreshes `.devcontainer/devcontainer.json`.

## Legacy file mapping

Use this as a quick reference while copying edits:

- `.agent-sandbox/docker-compose.yml` -> `.agent-sandbox/compose/user.override.yml` and `.agent-sandbox/compose/user.agent.<agent>.override.yml`
- `.devcontainer/docker-compose.yml` -> `.agent-sandbox/compose/user.override.yml`, `.agent-sandbox/compose/user.agent.<agent>.override.yml`, and possibly `.devcontainer/devcontainer.user.json`
- `.agent-sandbox/policy-cli-<agent>.yaml` -> `.agent-sandbox/policy/user.policy.yaml` and `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
- `.agent-sandbox/policy-devcontainer-<agent>.yaml` -> `.agent-sandbox/policy/user.policy.yaml`, `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`, and the managed `.agent-sandbox/policy/policy.devcontainer.yaml` supplied by `init`
