# 004: Layered Config for Non-Destructive Agent Switching

## Status

Proposed

## Context

Users currently switch agents by re-running `agentbox init` with a different agent. This rewrites generated compose files and can overwrite user customizations. It also makes experimentation costly because users must manually re-apply changes.

We need a switching model that preserves:

- Per-agent state volumes
- User policy edits
- User compose customizations

## Decision

Adopt a layered config model and add `agentbox switch --agent <name>`.

- Active target identity is `agent` with a single-active UX by default.
- Runtime mode remains separate runtime context, not part of active-target identity.
- Agentbox-managed files hold base/mode/agent defaults.
- User-owned overrides are layered: shared + optional mode + optional agent.
- Policy is layered similarly and merged at proxy runtime (single merge path).
- Runtime ownership is split by mode: CLI mode is agentbox-managed; devcontainer mode remains IDE-managed.

## Rationale

- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place.
- Layered compose aligns with Docker Compose merge semantics and keeps customization stable.
- Shared policy/compose overrides minimize duplication for project-level settings.
- Optional mode/agent overrides retain flexibility for specific integrations and auth/provider quirks.
- Separating active agent from runtime mode keeps the switching UX simple while leaving room for future runtime workflows.

## Consequences

**Positive:**
- Safe agent experimentation without destructive re-init.
- Reversible switching with persistent state.
- Clear contract about which files agentbox owns vs user owns.
- Lower policy duplication across agents in the same project.
- Better alignment with devcontainer reality (IDE controls runtime lifecycle).

**Negative:**
- More files in `.agent-sandbox/` to understand.
- Legacy layouts will require explicit re-init/manual carry-forward during this early phase.
- Additional CLI complexity (`switch`, layered backends, policy rendering, validation).
