# Task: m15.6 - Client Compatibility Shim

## Summary

Add a narrow agent-visible compatibility shim for service clients that need fake token-shaped setup while real
credentials stay proxy-only.

## Scope

- Define a renderer/runtime shape for non-secret compatibility hints emitted by service catalog expansion
- Add an explicit GitHub Git compatibility opt-in under authenticated `git` service entries
- Materialize deterministic fake Git credentials into the agent runtime only when the service entry opts in
- Pair shimmed GitHub Git rules with explicit `on_existing_header: replace` because the client may send a fake
  `Authorization` header
- Keep direct GitHub smart-HTTP injection unchanged and usable without shim config
- Keep all real secret values proxy-only; generated agent-visible config may contain fake values and secret IDs only
- Preserve service-level `merge_mode: replace` semantics for both rule fragments and compatibility hints
- Exclude arbitrary env-var injection, arbitrary placeholder substitution, request-body mutation, URL/query mutation,
  broad client auto-detection, GitHub REST wrapper behavior, and real credential-helper delivery

## Acceptance Criteria

- [ ] Catalog and renderer tests prove the compatibility opt-in emits deterministic agent-visible shim metadata with
      fake values and secret IDs only
- [ ] Tests prove resolved secret values never appear in rendered policy output, generated compatibility files, logs, or
      errors
- [ ] Tests prove a shimmed GitHub Git auth path emits `on_existing_header: replace`
- [ ] Tests prove ordinary GitHub smart-HTTP direct injection still emits `on_existing_header: fail` and no shim metadata
- [ ] Tests prove service `merge_mode: replace` removes prior compatibility hints for the replaced service
- [ ] Runtime/scaffold tests prove the shared compatibility config surface is readable by `agent` but does not expose the
      proxy secret mount or resolved secret files
- [ ] New shells can consume the generated fake Git compatibility environment; already-running processes are documented
      as not hot-updatable

## Applicable Learnings

- The service catalog should own provider semantics and emit canonical rendered fragments. The matcher and enforcer
  should stay generic and consume rule-scoped transform metadata.
- Direct GitHub Git auth uses `on_existing_header: fail`; replacement is reserved for an explicit compatibility shim
  that intentionally causes the client to send fake auth material.
- Rule-scoped policy metadata should be attached before host-record merge and dedupe so credential scope cannot become
  a host-wide side effect.
- Renderer-owned service contributions need owner tracking. Service-level `merge_mode: replace` should discard both
  host-rule fragments and any compatibility hints owned by that service.
- Agent runtime configuration that depends on process environment is not hot-updatable for already-running processes.
  A new shell, agent restart, or explicit re-source step is required.
- `internal/embeddata/templates/` is the source of truth for generated `agentbox init` and `agentbox switch` files.
  Checked-in `.agent-sandbox/` files are local runtime artifacts, not product support declarations.
- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs.

## Plan

### Files Involved

- `images/proxy/service_catalog.py` - add GitHub Git compatibility opt-in validation, emit compatibility hints, and
  switch shimmed Git auth transforms to `on_existing_header: replace`
- `images/proxy/policy_injection.py` - accept a small helper parameter for `on_existing_header` only if the catalog
  needs it to avoid duplicating canonical transform construction
- `images/proxy/client_shim.py` - new helper for compatibility hint normalization, dedupe, owner tracking, and safe
  shell-fragment rendering
- `images/proxy/render-policy` - carry service-owned compatibility hints through layered rendering, reject
  user-authored top-level `client_shim`, and optionally write the runtime compatibility file
- `images/proxy/entrypoint.sh` - render or clear the compatibility runtime file before the proxy becomes healthy
- `images/base/agentbox-git-askpass.sh` - new fake-only Git askpass helper that returns deterministic placeholder
  credentials for the opted-in GitHub flow
- `images/base/shell-init.sh` - source the generated compatibility shell fragment for new zsh sessions
- `images/base/Dockerfile` - install the fake askpass helper and any shell-init support files
- `internal/embeddata/templates/compose/base.yml` - add a non-secret compatibility config volume shared from `proxy` to
  `agent`
- `internal/scaffold/compose.go` - ensure generated and synced base compose layers include the compatibility volume and
  static agent/proxy environment paths
- `internal/scaffold/init_test.go` and `internal/scaffold/sync_test.go` - cover generated and repaired runtime mounts
- `images/proxy/tests/test_service_catalog.py` - catalog coverage for opt-in validation, direct versus shimmed auth, and
  emitted hint shape
- `images/proxy/tests/test_render_policy.py` - layered renderer coverage for rendered `client_shim`, merge/replace
  behavior, and generated shell output
- `images/proxy/tests/test_enforcer.py` - add or reuse coverage proving `replace` overwrites an existing fake
  `Authorization` header without leaking the real secret

### Approach

Keep the first compatibility shim GitHub Git-specific. That stays aligned with M15's first supported rollout and avoids
inventing a generic `env:` policy surface that can set arbitrary agent environment variables. Env-token SDK and CLI
shims should wait for a concrete service target and provider-specific request shape.

Add an explicit compatibility opt-in under authenticated GitHub Git auth. The exact policy spelling should be stable
and narrow:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
        client_shim:
          kind: git-askpass
```

Only `kind: git-askpass` is accepted in this task. Reject `client_shim` on unauthenticated `git.access: read`, reject it
outside GitHub repo-scoped `git.auth`, and reject unknown `client_shim` keys. This opt-in should not be inferred from
the presence of `git.auth.secret`; direct injection remains the default.

When compatibility is enabled, the catalog should emit the same Git smart-HTTP rule set as authenticated GitHub Git
auth, but with the canonical transform using explicit replacement:

```yaml
transform:
  request:
    headers:
      Authorization:
        secret: github.agent-sandbox.push-token
        transform:
          type: basic
          username: x-access-token
    on_existing_header: replace
```

That replacement is required because the fake Git setup may cause the client to send an `Authorization` header before
the proxy sees the request. The enforcer already knows how to replace existing headers; M15.6 should make the catalog
emit that behavior only for shimmed rules.

The rendered compatibility IR should be renderer-owned and non-secret. A representative shape:

```yaml
client_shim:
  version: 1
  hints:
    - service: github
      surface: git
      kind: git-askpass
      host: github.com
      username: x-access-token
      fake_password: agentbox-proxy-managed
      secrets:
        - github.agent-sandbox.push-token
```

Do not accept authored top-level `client_shim` from policy files. Policy authors can already set arbitrary agent
environment through compose overrides; this renderer-owned channel should only reflect service catalog decisions so it
stays tied to injection rules and replacement semantics.

The proxy entrypoint should write a deterministic shell fragment to a shared non-secret runtime path, for example:
`/run/agentbox/client-compat/env.zsh`. If there are no hints, it should write a no-op file or remove stale content so an
older shim does not survive a policy change. The fragment may export fake values and the askpass path, such as:

```sh
export AGENTBOX_GIT_FAKE_USERNAME='x-access-token'
export AGENTBOX_GIT_FAKE_PASSWORD='agentbox-proxy-managed'
export GIT_ASKPASS='/usr/local/bin/agentbox-git-askpass'
export GIT_TERMINAL_PROMPT='0'
```

The fake askpass helper must not resolve or read secrets. It should only return deterministic placeholders for GitHub
username/password prompts and should return an empty value for unrelated prompts. The proxy remains the only component
that resolves `github.agent-sandbox.push-token`.

Add a named compatibility volume to the managed base compose layer. Mount it read/write into `proxy` and read-only into
`agent`. This volume must not be confused with the proxy secret mount: it contains only fake values, shell exports, and
secret IDs. Existing generated runtimes should be repaired through scaffold sync, the same way M15.3 repaired managed
base layers for proxy secret mounts.

`images/base/shell-init.sh` should source the generated shell fragment for new zsh sessions when the file exists. Do
not claim this hot-updates already-running agent processes. Direct `agentbox exec <command>` invocations that bypass
zsh will not automatically source shell init; keep that limitation explicit for M15.8 docs instead of changing
`agentbox exec` quoting behavior in this task.

Testing should stay mostly unit-level in M15.6. M15.7 owns the broader integration and boundary tests, but this task
should still prove:

- direct GitHub auth and shimmed GitHub auth render different `on_existing_header` values
- shim metadata is emitted only on explicit opt-in
- generated compatibility shell fragments contain no resolved secret values
- replacing an existing fake `Authorization` header remains covered by enforcer tests
- runtime compose gives the agent read-only access to the compatibility volume and no access to the secret mount

### Implementation Steps

- [ ] Add a `client_shim.py` helper with canonical hint validation, dedupe keys, redaction-safe serialization, and
      shell quoting
- [ ] Extend render state with owner-tracked compatibility hints
- [ ] Reject user-authored top-level `client_shim` in input policy layers
- [ ] Extend service replacement logic so `merge_mode: replace` discards old hints owned by that service
- [ ] Add GitHub `git.auth.client_shim.kind: git-askpass` validation in the service catalog
- [ ] Emit GitHub compatibility hints only when the explicit compatibility opt-in is present
- [ ] Parameterize GitHub auth transform construction so direct auth keeps `fail` and shimmed auth uses `replace`
- [ ] Add `render-policy` support for writing the compatibility shell fragment while keeping normal policy rendering
      unchanged for callers that do not request the sidecar output
- [ ] Update the proxy entrypoint to write or clear the compatibility runtime file during startup
- [ ] Add the fake-only Git askpass helper to the base image
- [ ] Source the generated compatibility shell fragment from `images/base/shell-init.sh`
- [ ] Add the shared compatibility named volume and static path environment to the base compose template
- [ ] Update scaffold sync helpers to repair older managed base compose layers with the compatibility volume
- [ ] Add service catalog tests for direct auth, shimmed auth, invalid compatibility shapes, and emitted hints
- [ ] Add renderer tests for layered hint merge, service replacement, top-level `client_shim` rejection, and shell
      output redaction
- [ ] Add or extend enforcer tests for fake `Authorization` replacement on shimmed rules
- [ ] Add scaffold tests proving proxy read/write and agent read-only compatibility volume mounts without secret mount
      exposure
- [ ] Run `/opt/proxy-python/bin/python3 -m unittest discover -s images/proxy/tests -p 'test_*.py'`
- [ ] Run `go test ./...`

### Open Questions

- Resolved for this plan: use `kind: git-askpass` as the first shim target, not a generic env-var surface. A generic
  env-token system needs a concrete provider target and should not be smuggled into GitHub Git work.
- Resolved for this plan: direct GitHub smart-HTTP auth remains the default and keeps `on_existing_header: fail`.
  `client_shim` is opt-in because replacement weakens the existing-header guardrail.
- Resolved for this plan: m15.6 does not implement GitHub REST auth or stock `gh` support. M16 owns the REST wrapper
  direction, and M18 owns residual real credential-helper delivery.
- Open during implementation: whether sourcing only from zsh is enough for the first usable shim. The conservative
  default is to avoid changing `agentbox exec <command>` semantics in this task and document the new-shell/restart
  requirement.

## Outcome

### Acceptance Verification

Pending implementation.

### Learnings

Pending implementation.

### Follow-up Items

- `m15.7` should add end-to-end coverage for a shimmed request path using the generated fake runtime config.
- `m15.8` should document that compatibility shim changes require a new shell, agent restart, or explicit re-source step
  for already-running processes.
