# m8: Agent Switching Without Data Loss

Make it easy to switch between supported agents (Claude, Codex, Copilot) without losing:

- Agent state volumes (credentials, history, tool state)
- User policy customizations
- User Docker Compose customizations

## Problem

Current workflow is destructive for users who customize their setup:

- `agentbox init` recopies templates and overwrites compose/policy files.
- Users can keep only one active generated setup at a time.
- Trying another agent often means re-running init and manually re-applying edits.

This creates friction for experimentation and increases risk of accidental config loss.

## Goals

- Add a first-class `agentbox switch --agent <name>` workflow.
- Preserve all existing agent volumes when switching.
- Preserve user customizations across switches by separating managed files from user-owned files.
- Keep switching reversible and fast (switch away, switch back, no rebuild/reinit).
- Support both `cli` and `devcontainer` modes.

## Non-Goals

- Running multiple agents concurrently in one compose project (can be future work).
- Unifying agent-specific auth/config semantics (`.claude`, `.codex`, `.copilot`) into one shared home.
- Solving arbitrary malformed/manual compose edits with zero constraints.

## Proposed Design

### 1) File ownership split (core decision)

Introduce explicit ownership boundaries:

- **Managed by agentbox (do not edit manually):**
  - `.agent-sandbox/compose/base.yml`
  - `.agent-sandbox/compose/agent-claude.yml`
  - `.agent-sandbox/compose/agent-codex.yml`
  - `.agent-sandbox/compose/agent-copilot.yml`
  - `.agent-sandbox/compose/active-agent.yml` (symlink or generated pointer file)
- **User-owned (never overwritten by init/switch):**
  - `.agent-sandbox/compose/user.override.yml`
- **Policy files (layered, user-owned + managed):**
  - Shared project override (user-owned): `.agent-sandbox/policy.shared.yaml`
  - Optional per-agent override (user-owned): `.agent-sandbox/policy.agent.<agent>.yaml`
  - Generated effective policy (managed): `.agent-sandbox/policy.effective.<mode>.<agent>.yaml`

Why this split: preserving arbitrary user edits in a single generated compose file is brittle. Keeping user edits in a dedicated override file is predictable and testable.

### 2) Compose execution model

`agentbox` should run compose with multiple files in stable order:

1. base
2. active agent file
3. user override

This keeps agent defaults switchable while preserving user customizations in the final merge layer.

### 3) Policy layering model

Policy should be built in layers to reduce duplication while keeping agent-specific flexibility:

1. Agent default policy (managed template or baked baseline)
2. Shared project override (`policy.shared.yaml`)
3. Optional per-agent override (`policy.agent.<agent>.yaml`)

`agentbox` generates an effective policy file used by compose mount:

- `.agent-sandbox/policy.effective.<mode>.<agent>.yaml`

Merge semantics:

- `services`: union with de-duplication
- `domains`: union with de-duplication
- Unknown keys: preserve and deep-merge where possible

Why this model: most project allowlist additions are cross-agent, but some agent auth/provider quirks still require agent-specific exceptions.

### 4) Switch command behavior

Add `agentbox switch --agent <claude|codex|copilot> [--mode cli|devcontainer]`:

- Validate requested agent is supported.
- Interactive mode:
  - If no flags are provided, prompt exactly two questions:
    - Which agent to use (`claude`, `codex`, `copilot`)
    - Which mode to use (`cli`, `devcontainer`)
  - If one flag is provided, prompt only for the missing value.
  - If both flags are provided, do not prompt.
  - Do not ask unrelated questions (no project name, IDE, or other init prompts).
- Ensure `policy.shared.yaml` exists and optional `policy.agent.<agent>.yaml` is respected.
- Regenerate effective policy for selected mode/agent.
- Update active agent pointer (`active-agent.yml`) and policy mount reference to effective policy.
- Recreate only affected services if running (`docker compose up -d`).
- Never call `down --volumes`.

### 5) Volume preservation guarantees

- Keep agent-specific named volumes (`claude-state`, `codex-state`, `copilot-state`).
- Switching only changes which agent volume is mounted by active agent compose layer.
- Existing volumes remain intact and reusable when switching back.

### 6) Breaking-change rollout (existing installs)

Use a simple, explicit breaking-change path for early development:

- No automatic migration command.
- `agentbox switch` and updated `agentbox init` target only the new layered layout.
- If legacy single-file setup is detected, return a clear error with steps:
  - Re-run `agentbox init` (new layout)
  - Optionally copy relevant custom entries manually into `user.override.yml` and `policy.shared.yaml`

Rationale: automated migration adds complexity and edge cases that are not justified at current project maturity.

## Alternatives Considered

### A) Keep single compose and patch in place with `yq`

- Pros: minimal file churn.
- Cons: fragile with comments, custom service structure, and non-standard edits; hard to guarantee no regressions.
- Rejected as primary path.

### B) Compose profiles for each agent

- Pros: one file, built-in compose feature.
- Cons: policy mapping and devcontainer integration are less clear; profile-specific user customization still needs layering.
- Deferred.

## Risks

- User confusion about which files are safe to edit.
- Devcontainer behavior differences when active-agent pointer changes.
- Policy merge surprises (e.g., users expecting replacement semantics instead of union).

## Mitigations

- Strong file headers (`managed` vs `user-owned`).
- `agentbox doctor`/validation checks for missing active files and invalid policy references.
- Focused upgrade docs with before/after examples.
- `agentbox policy render` command to preview effective merged policy before applying.
- BATS coverage for switch and non-destructive re-runs.

## Implementation Plan

### m8.1: Data model + CLI surface

- Add `agentbox switch` command and argument validation.
- Add internal representation for active agent/mode.
- Update `run-compose` to build `-f` stack in deterministic order.
- Add policy merge helpers and schema validation for merged output.
- Add interactive prompt flow for missing `--agent`/`--mode` values.

### m8.2: Init refactor to layered layout

- Change `agentbox init` to generate layered files once.
- Generate `user.override.yml` if absent; never overwrite if present.
- Generate `policy.shared.yaml` if missing.
- Generate optional `policy.agent.<agent>.yaml` only when needed.
- Generate effective policy file from layered inputs.

### m8.3: Legacy-layout guardrails

- Detect legacy single-file layout and fail fast with clear upgrade instructions.
- Provide manual mapping guidance from legacy files to new layered files.

### m8.4: Devcontainer support

- Update devcontainer templates to reference layered compose strategy.
- Ensure switching agent updates active file for devcontainer mode too.

### m8.5: Tests + docs

- Add BATS for:
  - switch preserves custom compose edits
  - switch preserves shared + per-agent policy overrides
  - effective policy merge is deterministic and de-duplicated
  - switch preserves volumes (no `down --volumes`)
  - init re-run is non-destructive
  - legacy-layout detection returns actionable upgrade guidance
  - switch with no flags prompts exactly two questions (agent + mode)
  - switch with one flag prompts once for the missing value
  - switch with both flags is non-interactive
  - invalid `--agent` / `--mode` values fail with clear errors
- Update README and agent docs with switching workflow.

## Success Criteria

- User can run `agentbox switch --agent codex` then `agentbox switch --agent claude` without losing prior auth/state.
- User modifications in `user.override.yml` survive `init`, `switch`, and `bump`.
- Existing shared/per-agent policy edits remain intact after switches.
- Legacy layout is detected with clear upgrade instructions.

## Open Questions

- Should `switch` auto-start/restart services, or require explicit `agentbox up -d`?
- Should shared policy always merge by union, or allow explicit subtract/deny semantics for advanced users?
- Should `destroy` keep agent state volumes by default and require `--purge-volumes` for destructive cleanup?
