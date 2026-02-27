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

- Agentbox-managed files hold base and agent-specific defaults.
- A dedicated user-owned compose override file is never overwritten.
- Policy is layered: shared project override + optional per-agent override + generated effective policy.
- Switching changes only the active agent layer/policy reference and restarts services if needed.

## Rationale

- Strong ownership boundaries are more reliable than patching arbitrary user-edited YAML in place.
- Layered compose aligns with Docker Compose merge semantics and keeps customization stable.
- A shared policy override minimizes duplication for project-level allowlist changes.
- Optional per-agent policy overrides retain flexibility for agent-specific auth/provider quirks.

## Consequences

**Positive:**
- Safe agent experimentation without destructive re-init.
- Reversible switching with persistent state.
- Clear contract about which files agentbox owns vs user owns.
- Lower policy duplication across agents in the same project.

**Negative:**
- More files in `.agent-sandbox/` to understand.
- Legacy layouts will require explicit re-init/manual carry-forward during this early phase.
- Additional CLI complexity (`switch`, policy rendering, validation).
