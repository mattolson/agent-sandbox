# 006: `credential_shim` Is Renderer-Owned

## Status

Accepted

## Context

`m15` introduces a compatibility-shim path so an agent inside the sandbox can run commands that
require client-supplied credentials (today: `git push`) without storing real tokens in the
container. The mechanism has two halves:

- The agent container exports placeholder env vars (for `git-askpass`, that is
  `GIT_ASKPASS`, `AGENTBOX_GIT_FAKE_USERNAME`, `AGENTBOX_GIT_FAKE_PASSWORD`, `GIT_TERMINAL_PROMPT`)
  so the client tool runs non-interactively with a known fake credential.
- The proxy injects the real credential at request time, replacing the fake one in flight under
  `on_existing_header: replace`.

That coupling raises a question: how does the agent learn which env vars to export, and from
where? Two shapes were considered:

1. Author the shim directly in policy. The user writes a top-level `credential_shim:` block
   listing the env exports they want active, and the agent sources it.
2. Render the shim from a service-catalog opt-in. The user writes
   `services[].git.auth.client_shim.kind: git-askpass`. The renderer emits a `credential_shim:`
   block alongside the rest of the rendered policy. The agent sources the renderer's output.

Both shapes can produce identical runtime behavior. The question is which one the policy
schema commits to.

## Decision

`credential_shim` is renderer-owned. Authored top-level `credential_shim` is rejected at
render time. The renderer is the only producer of the rendered `credential_shim` block, and it
only does so when a service catalog entry explicitly opts in via
`services[].git.auth.client_shim.kind` (currently only `git-askpass`).

The rendered payload is intentionally narrow:

```yaml
credential_shim:
  version: 1
  hints:
    - service: <name>
      surface: <name>
      kind: <name>
      host: <hostname>
      username: <agent-visible-username>
      fake_password: <agent-visible-placeholder>
      secrets:
        - <secret-id>
```

It contains no resolved secret values. Real values stay on the host secret directory and are
read only at request time inside the proxy.

## Rationale

- **The shim is paired with proxy-side replacement rules.** A `git-askpass` shim is only safe
  because the proxy is configured to overwrite the placeholder `Authorization` header before
  the request reaches the upstream. Authoring the shim independently of the policy that drives
  the replacement would let users export placeholder credentials with no matching replacement
  rule, creating a path where a real client tool walks the placeholder upstream and either
  fails noisily or — worse — succeeds against an attacker who happens to know the placeholder.
- **Coupling shim emission to a catalog entry keeps that pairing in one place.** When a user
  writes `git.auth.client_shim.kind: git-askpass`, the renderer flips both halves at once:
  emits the shim **and** switches the matching rules to `on_existing_header: replace`. There
  is no way to ship one without the other from valid authored input.
- **The set of legitimate shim kinds is small and known to the renderer.** `git-askpass` is
  the only kind today. Adding a new kind is a renderer change with explicit tests, not a
  documentation update. An authored-shim shape would invite arbitrary kinds and ad-hoc env
  exports that the proxy has no enforcement story for.
- **Stable identifier discipline.** Rejecting authored `credential_shim` keeps the same name
  available for the renderer-owned output without creating a name collision between supported
  and rejected fields. This mirrors the m15.5 boundary around `surfaces`/`access`/`auth`.

## Consequences

**Positive:**

- The shim-and-replace pairing cannot be partially configured. Either both halves are present
  in the rendered policy or neither.
- Future credential-injection work (provider API keys in `m17`, GitHub REST APIs in `m18`, and host credential helpers
  in `m20`) can define new shim kinds without adopting a generic env-export surface that would be hard to constrain.
- Rendered policy stays small. The `credential_shim` block only appears when something needs
  it, and the payload's only consumer is `/etc/agent-sandbox/shell-init.sh`.

**Negative:**

- Users who want a shim that the catalog does not support cannot ship one through policy
  alone. They have to either contribute a new `kind` to the renderer or fall back to the
  in-container credential-store path documented in `docs/git.md`.
- The renderer is the single source of truth for what env vars an agent shell sees from a
  shim. Anything outside that shape (`shell.d/`, dotfiles, etc.) is the user's responsibility
  and unrelated to the proxy's replacement rules.

## Follow-up

- `docs/policy/schema.md` "Renderer-owned fields" documents the rejection and the rendered
  payload shape so future readers do not look for an author-facing knob.
- Future credential milestones that add new `kind` values (e.g. a non-Git shim) should follow
  the same renderer-owned pattern. The decision applies to the field name, not to
  `git-askpass` specifically.
