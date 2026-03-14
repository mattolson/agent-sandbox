# Execution Log: m8.5 - Centralize Devcontainer Runtime Files

## 2026-03-14 04:50 UTC - Implementation complete

Reworked devcontainer mode so `.devcontainer/` is now only the IDE-facing shim. The managed runtime compose and policy layers moved under `.agent-sandbox/`, `devcontainer.json` now points at that centralized compose stack, and the CLI no longer scaffolds devcontainer-specific user compose or policy override files.

**Decision:** Keep `.devcontainer/devcontainer.user.json` as the only devcontainer-specific user extension point. Compose and policy customization now reuse the shared `.agent-sandbox` user override files.

**Decision:** `agentbox edit policy --mode devcontainer` now fails for the centralized layout instead of silently aliasing to the shared policy file. The mode flag should not imply a separate user surface when none exists.

**Decision:** Dropped the temporary `m8.4` compatibility branch entirely after confirming that milestone 8 has not shipped to users. Carrying an unreleased intermediate layout would add confusion with no real migration value.

**Learning:** Centralizing the runtime files made the docs and edit surfaces simpler immediately. The previous "managed files in one directory, user files in another" model was technically coherent but not user-coherent.

## 2026-03-14 04:19 UTC - Initial planning

User feedback on `m8.4` identified a real conceptual problem: sandbox runtime files are split between `.agent-sandbox/` and `.devcontainer/`, which forces users to understand cross-directory compose and policy layering. The follow-on task direction is to keep `.devcontainer/` as a thin IDE shim and centralize compose and policy runtime files under `.agent-sandbox/`.

**Decision:** Do not plan devcontainer-specific user compose or policy override files in this refactor. Keep only `.devcontainer/devcontainer.user.json` as a devcontainer-specific user extension surface, and reuse the shared `.agent-sandbox` override files elsewhere.

**Decision:** Update the milestone plan to make this centralization a first-class task (`m8.5`) and push legacy guardrails/docs/tests to a subsequent `m8.6` follow-up.
