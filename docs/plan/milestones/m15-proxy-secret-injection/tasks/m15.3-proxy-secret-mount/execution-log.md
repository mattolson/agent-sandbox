# Execution Log: m15.3 - Proxy Secret Mount

## 2026-05-04 02:06 UTC - Host Compose sanity passed

Ran the temporary host sanity script on a machine with Docker Compose 5.1.0. The script passed CLI and devcontainer
config validation, confirmed proxy-only secret mounts, confirmed the default host secret path interpolation, and
confirmed `compose config` does not create a missing secret directory.

**Issue:** The first script version used `--no-interpolate` for semantic source-path assertions, which made Compose
normalize the literal `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` expression as a relative path
under `.agent-sandbox/compose`.
**Solution:** Split the checks: grep the generated YAML for the authored variable expression, then run semantic
`compose config` assertions with an explicit absolute `AGENTBOX_SECRET_DIR` and with default interpolation.

**Learning:** `--no-interpolate` preserves authored Compose expressions, but it is not a faithful runtime-path check
for nested default expressions that represent absolute host paths after interpolation.

## 2026-05-04 01:54 UTC - Implementation complete

Implemented proxy-only file secret mounting in the managed compose scaffold. The base proxy service now receives
`${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` at `/run/secrets/agentbox` with
`bind.create_host_path: false`, plus `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox`. Managed policy, workspace,
and devcontainer bind mounts now use long-syntax bind mappings where the scaffold owns the file.

Added scaffold and sync tests for the proxy mount/env, agent non-exposure, long-syntax managed bind mounts, and repair
of older base compose layers. Documented `AGENTBOX_SECRET_DIR`, directory permissions, outside-workspace requirements,
and missing-directory startup behavior.

Verified with `go test ./...` and
`/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`.

**Issue:** Docker Compose validation could not run because the container does not have the `docker` CLI installed.
**Solution:** Recorded the gap as a follow-up and relied on semantic scaffold tests plus proxy tests in this environment.

**Learning:** Service volume handling needs a mixed string/mapping representation before security-sensitive bind mount
options can be added without breaking named-volume and user override scaffolds.

## 2026-05-03 15:57 UTC - Secret directory docs requirement resolved

Updated the plan to require docs stating that `AGENTBOX_SECRET_DIR` should stay outside the project directory and
outside any path mounted into the agent.

**Decision:** Treat this as an explicit m15.3 docs requirement, not a later optional documentation cleanup. The default
host path is outside normal project layouts, but custom paths inside the repo would undermine the proxy-only secret
boundary.

## 2026-05-03 15:56 UTC - Managed bind mount default broadened

Reviewed the current compose templates and confirmed agentbox is not using `bind.create_host_path: false` for existing
bind mounts. All managed templates currently use Compose short syntax for bind mounts and named volumes.

**Decision:** Broaden the m15.3 plan so `create_host_path: false` becomes the target default for agentbox-managed bind
mounts where Compose compatibility permits. This does not apply to named Docker volumes such as `proxy-state`,
`proxy-ca`, and agent state/history volumes, and agentbox should not rewrite existing user-owned override files.

**Rationale:** Silent host-path creation is undesirable for security and UX. A missing path usually means the scaffold,
sync, or user setup is wrong; creating an empty directory can hide the problem and weaken the runtime boundary.

## 2026-05-03 15:54 UTC - Runtime mount target renamed

Updated the planned in-container secret mount from `/run/agentbox/secrets` to `/run/secrets/agentbox`.

**Decision:** Use the conventional `/run/secrets/...` namespace while keeping the Agentbox-specific leaf directory.
This better matches container secret mount conventions and still keeps the source clearly proxy-owned and outside the
workspace.

## 2026-05-03 15:49 UTC - Initial task plan

Created the `m15.3` task plan from the milestone breakdown and reviewed current scaffold templates, compose generation
helpers, init/sync tests, m15.2 resolver behavior, layered config learnings, and proxy-as-enforcer architecture.

**Decision:** Plan the proxy secret mount in the managed base compose layer so both CLI and centralized devcontainer
stacks inherit the same proxy-only secret source.

**Decision:** Prefer Docker Compose long bind-mount syntax with `bind.create_host_path: false` to avoid short-form bind
mount behavior that can silently create a missing host directory.

**Observation:** The current scaffold compose model stores service volumes as `[]string`. Supporting the intended
missing-directory behavior requires preserving long-syntax volume mappings, so m15.3 is broader than a simple template
edit.

**Observation:** Existing runtime sync helpers already repair managed base policy mounts for older layered repos. The
secret mount and `AGENTBOX_SECRET_SOURCE` should follow that repair path so older generated runtimes move forward
without touching user-owned overrides.
