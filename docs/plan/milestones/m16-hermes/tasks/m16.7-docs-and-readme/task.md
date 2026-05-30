# Task: m16.7 - Hermes agent docs, README support matrix, and m16 done-marking

## Summary

Document Hermes end-to-end for users: `docs/agents/hermes.md` (setup, provider config, sandbox env vars, upgrade
path), `README.md` support-matrix row, milestone mark-done in `docs/plan/project.md` and `docs/roadmap.md`, plus
the host-side manual verification run that the milestone hinges on (init → up → real Hermes session →
restart-persistence of `HERMES_HOME`).

## Scope

**Included:**
- New `docs/agents/hermes.md` covering:
  - Intro paragraph: what Hermes is, link to README, link to upstream docs
  - **Provider configuration** — Hermes is provider-agnostic; users add the proxy service for their chosen
    provider (`claude` / `codex` / `gemini` / etc.) to `user.agent.hermes.policy.yaml`. Also document the
    Nous-specific opt-in: `inference-api.nousresearch.com` if using Nous Portal directly.
  - **Authentication** — two paths: `hermes login <provider>` (OAuth flow, credentials persist in
    `HERMES_HOME`) or direct env-var (`NOUS_API_KEY`, `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, etc.) added via
    `.agent-sandbox/compose/user.agent.hermes.override.yml`. Enumerate the supported provider env vars from m16.1
    discovery.
  - **Use Hermes** — `hermes chat`, brief subcommand overview, mention `HERMES_YOLO_MODE=1` is on by default so no
    permission prompts.
  - **State persistence** — `HERMES_HOME=/home/dev/.hermes` mounted on a named volume; learned skills, persona,
    sessions persist across `agentbox down && agentbox up`.
  - **Sandbox-specific env vars** — `HERMES_YOLO_MODE`, `HERMES_DISABLE_LAZY_INSTALLS` and why each is set.
    Also note the `/usr/local/bin/hermes` wrapper that intercepts `update` and `uninstall` (see Upgrade path).
  - **Upgrade path** (revised after the m16.3 reversal — see m16.3 execution log for the HERMES_MANAGED rollback):
    - Why `hermes update` is disabled (venv is baked into the image and read-only; reproducible-image story).
    - What to do instead: CI version-check workflow opens a PR bumping `HERMES_VERSION` → merge → image is rebuilt
      and republished → `agentbox bump` to pull new digest → `agentbox down && agentbox up`. `HERMES_HOME` volume
      persists across the swap.
    - Migrations are user-invoked, separate from `update`: `hermes gateway migrate-legacy`, `hermes claw migrate`,
      `hermes setup` (re-run setup wizard). Document that release notes from upstream will call out when these are
      needed.
    - Pre-upgrade snapshot: `hermes backup` writes a zip of `HERMES_HOME`; `hermes import` restores.
  - **Optional opt-in domains** — `api.github.com` (skills hub), `app.honcho.dev` (Honcho memory),
    `cloud.langfuse.com` (Langfuse observability), `firecrawl-gateway.nousresearch.com` (Firecrawl skill). Each
    documented with a short why-when-add note.
- `README.md` updates:
  - Add Hermes row to the support-matrix table (line 35-ish): `:heavy_check_mark:` for CLI, `:no_entry_sign:` for
    VS Code and JetBrains.
  - Add "No IDE extensions available for Hermes" to the known-blockers list (line 43-ish).
  - Add a `- [Hermes](docs/agents/hermes.md)` link to the agent-specific-setup section (line 135-ish).
- Mark m16 done:
  - `docs/plan/project.md`: change `### m16-hermes` heading to `### m16-hermes (done)`.
  - `docs/roadmap.md`: change `## m16: [Hermes]... (planned)` to `(done)`.
- **Host-side end-to-end manual verification** (the milestone's load-bearing acceptance step). Walk through:
  - `agentbox init --agent hermes --mode cli` in a fresh project directory
  - Add a provider service to `user.agent.hermes.policy.yaml` (use whichever provider the user has a key for)
  - Configure provider auth (env var or `hermes login`)
  - `agentbox up`, exec in, run `hermes chat` and a short interaction
  - Observe `/home/dev/.hermes/` populates (sessions, learned skills, etc.)
  - `agentbox down && agentbox up`, re-exec, confirm state persists (e.g., `hermes` resumes / sessions visible)
  - Try `hermes update --yes` to confirm the wrapper's refusal lands as expected

**Explicitly out of scope:**
- New agent images. m16.7 is documentation + mark-done + manual verification.
- (Exception, added 2026-05-29:) the m16.3 `HERMES_MANAGED` reversal — the wrapper script and Dockerfile fix were
  carried in this task because end-to-end testing here is what surfaced the bug. See m16.3 execution log for
  details.
- Backfilling docs for other agents. If hermes.md surfaces patterns that would improve pi.md or opencode.md, those
  are separate work.

## Acceptance Criteria

- [ ] `docs/agents/hermes.md` exists, covers all the sections listed above, and follows the structure used by
      pi.md/opencode.md (where applicable).
- [ ] All links in hermes.md resolve (relative paths to `../../README.md`, anchors within the doc).
- [ ] `README.md` supported-agents table includes Hermes row with `[Hermes](docs/agents/hermes.md)` link.
- [ ] `README.md` known-blockers list mentions Hermes IDE situation.
- [ ] `README.md` agent-specific-setup link list includes Hermes.
- [ ] `docs/plan/project.md`'s m16 heading reads `### m16-hermes (done)`.
- [ ] `docs/roadmap.md`'s m16 heading reads `## m16: [Hermes](...) support (done)`.
- [ ] Host-side end-to-end manual run completes and `HERMES_HOME` state persists across restart.
- [ ] `hermes update --yes` and `hermes uninstall --yes` print the wrapper's refusal and do not reach pip.

## Applicable Learnings

From the milestone so far:

- **Pi-as-reference for doc structure.** pi.md is the closest model: short intro → provider-config → auth → use →
  packages section. Hermes adds upgrade-path documentation, optional-features documentation, and a richer provider
  list, but the bones match.
- **Provider services in user policy, not the managed compose layer.** m16.3 made the `hermes` service minimal
  (just `hermes-agent.nousresearch.com`); users add their chosen provider's service (`claude`, `codex`, etc.) and
  any Hermes-specific opt-ins themselves. Document this clearly.
- **Upgrade-path enforcement is a wrapper script, not `HERMES_MANAGED`** (this is the post-m16.3 reversal). The
  wrapper at `/usr/local/bin/hermes` catches the `update` and `uninstall` subcommands and prints a message pointing
  users at `agentbox bump`. The original `HERMES_MANAGED=AgentSandbox` approach blocked `hermes setup` and broke
  first-run config; see m16.3 execution log for the full story. Quote the wrapper's message verbatim in the doc.
- **Direct env-var auth uses the user override file.** From m16.4 follow-up: there's no `environment:` block in the
  managed compose layer. Users add provider keys to `.agent-sandbox/compose/user.agent.hermes.override.yml`. This
  was an intentional design choice (matches Pi/OpenCode), document it.

## Plan

### Files Involved

To create:
- `docs/agents/hermes.md`

To modify:
- `README.md` (3 spots: support matrix row, known blockers, setup link list)
- `docs/plan/project.md` (1 line: m16 heading)
- `docs/roadmap.md` (1 line: m16 heading)

### Approach

1. **Write `docs/agents/hermes.md` from scratch**, modeled on pi.md but with the additional sections specific to
   Hermes (upgrade path, sandbox env vars, optional opt-in domains). Aim for thorough-but-tight; pi.md is ~70 lines,
   hermes.md will be ~120-150.
2. **README updates** as three small edits.
3. **Mark m16 done** in two files.
4. **Hand off the host-side manual verification** with a clear checklist for the user to run through. The user has
   a real provider key on host and can do the actual chat session; I can't from in here.

### Implementation Steps

- [ ] Draft `docs/agents/hermes.md`.
- [ ] Update `README.md` support matrix (add Hermes row).
- [ ] Update `README.md` known-blockers list.
- [ ] Update `README.md` agent-specific-setup link list.
- [ ] Mark m16 done in `docs/plan/project.md`.
- [ ] Mark m16 done in `docs/roadmap.md`.
- [ ] Verify links in hermes.md resolve (`grep` for relative paths, eyeball anchors).
- [ ] Send the user a manual-verification checklist (separate from this task.md to keep the diff clean).
- [ ] After the user confirms verification, commit the milestone-closing work.

### Open Questions

- **Hermes IDE story.** I'm assuming `:no_entry_sign:` for both VS Code and JetBrains because Hermes doesn't ship
  an IDE extension. If you're aware of an in-progress or third-party extension, let me know and I'll reflect that
  in the matrix.
- **Provider env-var enumeration.** The m16.1 discovery captured the full list (Nous, OpenRouter, OpenAI,
  Anthropic, Gemini, Novita, OLLAMA, Honcho, Google API). Document all of them, or just the common 3-4
  (Nous/OpenRouter/OpenAI/Anthropic) to keep the doc focused? **Recommendation:** document the common 4 in the
  main flow, list the rest in a collapsible "Other providers" section or a brief table. Final call at execution.

## Outcome

(To be filled in on completion.)

### Acceptance Verification

- [ ] All acceptance criteria above

### Learnings

(To be added on completion, also appended to `docs/plan/learnings.md`.)

### Follow-up Items

(To be added on completion.)
