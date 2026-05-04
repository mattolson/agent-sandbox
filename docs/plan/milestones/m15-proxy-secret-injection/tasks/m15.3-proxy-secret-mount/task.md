# Task: m15.3 - Proxy Secret Mount

## Summary

Wire the host file-backed secret directory into the runtime so only the proxy can read it.

## Scope

- Mount `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` read-only into the proxy as
  `/run/secrets/agentbox`
- Set the proxy secret-source environment to the mounted file backend
- Ensure the agent service does not mount the secret directory
- Add scaffold/runtime tests for generated compose output
- Exclude request injection behavior

## Acceptance Criteria

- [ ] Generated CLI and devcontainer compose stacks mount the secret directory into `proxy` only
- [ ] Compose tests prove `agent` has no `/run/secrets/agentbox` or host secret-directory mount
- [ ] Missing local secret directories have clear documented behavior rather than silent Docker-created surprises

## Applicable Learnings

- The proxy sidecar is the enforcement boundary. Secret resolution and secret mounts belong in proxy-owned runtime
  surfaces, not the agent container or workspace.
- `internal/embeddata/templates/` is the source of truth for generated `agentbox init` and `agentbox switch` files.
  Checked-in `.agent-sandbox/` files are local runtime artifacts, not product support declarations.
- Regression tests over rendered compose should assert semantic invariants rather than one exact YAML shape because
  Compose and YAML tooling can normalize environment and volume nodes differently.
- Relative paths in Docker Compose files are resolved from the compose file's directory. The managed compose files live
  under `.agent-sandbox/compose/`, so repo-relative mounts use `../..` while policy mounts use `../policy/...`.
- The m15.2 file resolver expects `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox` and reads secret files at
  request time.

## Plan

### Files Involved

- `internal/embeddata/templates/compose/base.yml` - add the proxy-only secret bind mount and `AGENTBOX_SECRET_SOURCE`
  environment entry
- `internal/scaffold/compose.go` - teach managed compose read/write helpers to preserve long-syntax service volumes,
  prefer `bind.create_host_path: false` for agentbox-managed bind mounts, and ensure older generated base layers are
  repaired during sync
- `internal/scaffold/init_test.go` - assert new CLI and devcontainer scaffolds include the proxy mount/env and exclude
  agent mounts
- `internal/scaffold/sync_test.go` - assert runtime sync repairs older base compose layers with the secret mount/env
- `docs/cli.md` - document `AGENTBOX_SECRET_DIR`, the default directory, the requirement to keep the secret directory
  outside the project/workspace tree, and the expected missing-directory behavior
- `docs/troubleshooting.md` - add a short fix path for missing proxy secret directory startup failures if the CLI docs
  section is not enough during implementation

### Approach

Put the secret source on the managed base compose layer because both CLI and centralized devcontainer stacks include
that layer. The agent-specific layers should stay unchanged unless tests reveal they need compatibility cleanup.

Use Docker Compose long bind-mount syntax for the proxy secret directory:

```yaml
- type: bind
  source: ${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}
  target: /run/secrets/agentbox
  read_only: true
  bind:
    create_host_path: false
```

The `create_host_path: false` flag is the important part. Short-form bind mounts can silently create missing host paths,
which is usually the wrong default for agentbox-managed mounts: a missing policy file, workspace path, IDE directory,
dotfiles directory, or secret directory should be an explicit setup problem rather than a silently created empty path.
Named Docker volumes such as `proxy-state`, `proxy-ca`, and agent state/history volumes are different; they are meant to
be created and managed by Docker, so this setting does not apply.

Use m15.3 to make this the default for agentbox-managed bind mounts while leaving arbitrary user-authored override
mounts under user control. The generated user override examples can show the safer long syntax, but agentbox should not
rewrite existing user-owned override files.

Documentation must explicitly tell users to keep the secret directory outside the project directory and outside any path
mounted into the agent. The default `${HOME}/.config/agent-sandbox/secrets` satisfies that for normal project layouts;
custom `AGENTBOX_SECRET_DIR` values inside the repo undermine the proxy-only boundary.

Documentation should tell users to create the secret directory with:

```bash
mkdir -p "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
chmod 700 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
```

Set `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox` on the proxy service in the same base layer. This keeps m15.4
able to construct `SecretResolver.from_env()` without knowing where the host directory came from.

The scaffold code currently models service `volumes` as `[]string`. Long-syntax bind mounts are YAML mappings, so the
implementation should add a small volume-list representation that can preserve both short-form string entries and
mapping entries. Keep helper APIs ergonomic for existing named-volume and string checks so current policy and agent
volume logic does not become brittle.

Existing generated runtimes need to be repaired by sync paths. Extend the existing base-runtime repair helper to ensure
both the shared policy mount and the proxy secret mount/env. This lets lifecycle commands and `agentbox switch` bring an
older layered repo forward without overwriting user-owned overrides.

Tests should assert semantic invariants:

- The base proxy service has `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox`
- The base proxy service has one read-only bind mount from
  `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` to `/run/secrets/agentbox`
- That bind mount sets `create_host_path: false`
- Generated `agent` services in base, agent, and devcontainer mode layers do not reference `/run/secrets/agentbox`,
  `AGENTBOX_SECRET_DIR`, or the default host secret path
- Sync repairs an older base layer that lacks the mount/env

Do not wire the mount into request injection. Do not add secret values, secret file creation, or a secret management CLI
in this task.

### Implementation Steps

- [x] Add constants/helpers for the proxy secret mount source, target, and `AGENTBOX_SECRET_SOURCE`
- [x] Extend compose volume parsing/writing to preserve both short-form strings and long-syntax bind mounts
- [x] Audit agentbox-managed bind mounts and convert them to long syntax with `bind.create_host_path: false` where
      Compose compatibility permits
- [x] Add the proxy secret bind mount and secret-source env var to the base compose template
- [x] Update base compose generation and sync repair helpers to ensure the mount/env on existing managed base layers
- [x] Add CLI scaffold tests for proxy-only mount/env and no agent secret mount
- [x] Add devcontainer scaffold tests for the same proxy-only effective stack invariants
- [x] Add sync tests proving older base compose files are repaired
- [x] Document `AGENTBOX_SECRET_DIR`, default path, outside-project requirement, directory creation, permissions, and
      missing-directory failure mode
- [x] Run `go test ./...`
- [x] If Docker Compose is available, sanity-check rendered compose config against the same semantic invariants. Host
      validation passed with Docker Compose 5.1.0.

### Open Questions

- Resolved: host-side validation passed with Docker Compose 5.1.0. The sanity check used explicit absolute
  `AGENTBOX_SECRET_DIR` values for semantic config validation because `--no-interpolate` leaves the nested default
  expression literal and Compose normalizes that literal as a relative path.
- Resolved: docs must explicitly warn that custom `AGENTBOX_SECRET_DIR` values should stay outside the workspace and
  any agent-mounted path. The generated compose can keep the default safe, but users can undermine the boundary with a
  custom path inside the repo.

## Outcome

### Acceptance Verification

- [x] Generated CLI and devcontainer compose stacks mount `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}`
      read-only into `proxy` as `/run/secrets/agentbox` and set
      `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox`
- [x] Scaffold and sync tests assert generated `agent` services do not reference `/run/secrets/agentbox`,
      `AGENTBOX_SECRET_DIR`, or the default host secret path
- [x] `docs/cli.md` and `docs/troubleshooting.md` document directory creation, permissions, outside-workspace
      requirements, and missing-directory startup behavior
- [x] `go test ./...`
- [x] `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [x] Host-side `m15-host-sanity.sh` with Docker Compose 5.1.0

### Learnings

- Long-syntax Docker Compose service volumes require a mixed string/mapping representation. Keeping service volumes as
  raw YAML nodes preserves existing short-form named volumes while allowing security-sensitive bind mounts to opt into
  `bind.create_host_path: false`.
- For Compose sanity checks involving nested default expressions, validate the generated YAML expression directly, then
  run semantic `compose config` assertions with an explicit absolute environment value. `--no-interpolate` is useful
  for preserving authored expressions, but it is not a faithful runtime-path check.

### Follow-up Items

- None.
