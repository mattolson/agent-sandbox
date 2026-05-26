# Task: m16.1 - Hermes Discovery

## Summary

Resolve the open questions about Hermes that the public docs do not answer, so subsequent tasks in m16 can be
implemented against known specifics rather than guesses.

## Scope

Read the upstream [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) repo to answer the
seven questions listed under **Open Questions** below. Produce a single discovery note under this task folder. Do not
write image, template, proxy, or CLI changes in this task — those land in m16.2+ once the unknowns are pinned down.

## Acceptance Criteria

- [ ] `discovery.md` exists in this task folder and answers every question under **Open Questions**, citing upstream
      file paths (and commit SHA) for each fact.
- [ ] For any question that cannot be answered from upstream source alone, the note records what was checked, what is
      still unknown, and a proposed next step (upstream issue, ask in Discord, defer to runtime spike).
- [ ] The note names the specific env vars, domains, state paths, and feature flags that m16.2-m16.4 will consume, in
      the exact strings they will be referenced by.
- [ ] A version-pinning recommendation is recorded (release tag, commit SHA, or accept-main-with-unstable-label) with
      reasoning.

## Applicable Learnings

- `learnings.md` is silent on agent-discovery process specifically; the closest applicable note is the m11/m12
  observation that the add-agent skill provides a comprehensive checklist — this discovery exists to feed that
  checklist with concrete values rather than placeholders.
- For provider-agnostic agents (Pi, OpenCode), the agent service in the proxy covers only the agent's own
  infrastructure; provider domains are user-managed. The discovery should confirm whether Hermes follows the same shape
  or has its own learning-loop endpoint that's mandatory.

## Plan

### Files Involved

This task produces, not consumes, files:
- `docs/plan/milestones/m16-hermes/tasks/m16.1-discovery/discovery.md` (new, the output)
- `docs/plan/milestones/m16-hermes/tasks/m16.1-discovery/execution-log.md` (running log)

Optionally creates (and deletes when done):
- `/tmp/hermes-agent/` — a working clone of the upstream repo, used as the source of truth for reading. Not committed.

### Approach

Two-track read strategy:

1. **Primary: local clone.** `git clone https://github.com/NousResearch/hermes-agent.git /tmp/hermes-agent` and read
   files with `Read` and `Bash` (grep, find, etc.). WebFetch summarizes content even when asked for verbatim text, so
   it's not reliable for grepping for specific env var names or extracting exact installer logic. Local reads are
   exact and greppable.
2. **Fallback: targeted WebFetch.** If the proxy policy blocks the clone (the agent container's outbound is restricted),
   fall back to WebFetch against `https://raw.githubusercontent.com/NousResearch/hermes-agent/main/<path>` with
   narrowly scoped prompts ("name every environment variable referenced in this file") rather than verbatim dumps. The
   README is already known to be fetchable this way.

Pin the discovery to a specific upstream commit SHA recorded at the top of `discovery.md`, not "as of today", so the
findings remain interpretable when m16.2+ executes weeks later.

### Implementation Steps

- [ ] Try `git clone https://github.com/NousResearch/hermes-agent.git /tmp/hermes-agent`. If it succeeds, record the
      `HEAD` SHA and skip the WebFetch fallback. If it fails, document the failure mode in the execution log and
      proceed with WebFetch.
- [ ] Skim the repo structure (`ls -R`, top-level README, docs folder) to map where each open question is likely
      answered.
- [ ] Read `scripts/install.sh` (and `install.ps1` only as needed) to answer the install/binary/version-pinning
      questions.
- [ ] Grep source for `os.Getenv`, `process.env.`, `os.environ.`, or the language's equivalent to enumerate auth and
      provider env vars.
- [ ] Grep source for hardcoded hostnames and HTTP base URLs to enumerate Hermes infrastructure domains. Cross-check
      against `nousresearch.com` and any `*.nousresearch.com` subdomains.
- [ ] Locate the state directory by searching for path constants (`~/.hermes`, XDG_*, `os.path.expanduser`, etc.).
- [ ] Search for confirmation prompts, shell-exec gating, or feature flags that would block yolo mode in-container
      (analogous to Codex's `--sandbox-mode none` or OpenCode's `permission: allow` config).
- [ ] Search for any auto-update, telemetry, or LSP-download behavior triggered at startup. Note the env vars or
      config keys that disable them.
- [ ] For each question, write the answer into `discovery.md` with an upstream file:line citation and a quoted excerpt
      where helpful.
- [ ] If `/tmp/hermes-agent` was used, delete it (or leave with a note) — it must not be committed.
- [ ] Update m16 milestone.md if the discovery surfaces facts that should adjust m16.2-m16.7 scope (e.g., extra env
      vars to surface in the compose template, a mandatory learning-loop endpoint that changes the proxy story).

### Open Questions

These are the seven questions whose answers `discovery.md` must record:

1. **Binary layout.** What does `scripts/install.sh` actually produce? Is Hermes a single Go binary, a Python entry
   point, a Node CLI, a shell wrapper around something else? Where does it land on disk? What does the install script
   require (interpreters, runtime libraries)?
2. **Versioning.** Does upstream publish release tags or only track `main`? If tags exist, is there a "latest stable"
   convention? What's the cleanest way to pin a specific version in the Dockerfile build (`HERMES_VERSION` arg)? If
   only `main`, what's the recommendation — pin a commit SHA, accept "unstable", or push upstream to tag?
3. **Auth env vars.** What env vars does Hermes read for provider auth (e.g., `NOUS_API_KEY`, `OPENROUTER_API_KEY`,
   `OPENAI_API_KEY`, `NOVITA_API_KEY`, etc.)? Are there Hermes-specific env vars (`HERMES_*`) that gate behavior? Does
   it support a config file as an alternative? Login command vs. env-only?
4. **Infrastructure domains.** What hostnames does Hermes contact directly, separate from the user-chosen provider?
   Candidates: a Nous Portal model registry, a learning-loop sync endpoint, an update check, telemetry. Each one
   either lands in the `hermes` service `SERVICE_DOMAINS` entry or the milestone's risk section.
5. **State directory.** Where are learned skills, persona, and session memory written? Is it a single dir (e.g.,
   `~/.hermes/`) or XDG-spread (`~/.config/hermes`, `~/.local/share/hermes`, `~/.cache/hermes`)? This determines the
   volume mount(s) in the compose template.
6. **Sandbox / yolo flag.** Does Hermes prompt before shell-exec, or run actions unattended by default? If it prompts,
   what's the flag or config key to disable confirmation in a sandbox?
7. **Startup network behavior.** Does Hermes auto-update or download anything (model registries, LSP servers,
   docs caches) on startup? What env vars or config keys disable each behavior? OpenCode required two such
   (`OPENCODE_DISABLE_AUTOUPDATE`, `OPENCODE_DISABLE_LSP_DOWNLOAD`) — Hermes likely has its own set.

### Definition of Done

- `discovery.md` exists, dated, pinned to an upstream commit SHA.
- All seven open questions have answers (or recorded "unknown" with next-step proposal).
- Strings (env var names, domain names, state paths, feature flags) are exact, copyable into m16.2-m16.4 code without
  reinterpretation.
- The milestone plan (m16-hermes/milestone.md) is updated if discovery surfaces scope changes for downstream tasks.

## Outcome

Completed 2026-05-25. Findings recorded in `discovery.md`, pinned to upstream commit
`cea87d9139044870752aafdcdf9ca253049ae175`.

### Acceptance Verification

- [x] discovery.md exists with answers to all seven questions
- [x] Upstream commit SHA is recorded
- [x] Strings (env vars, domains, state paths, feature flags) are exact and copyable into downstream tasks
- [x] Milestone plan updated with a Changes entry pointing to discovery.md (no scope shift large enough to warrant
      rewriting m16.2-m16.7 inline; downstream tasks reference discovery.md as input)

### Learnings

Appended to `docs/plan/learnings.md`:
- For agents with runtime self-modification behavior (lazy installs, plugin auto-install), the sandbox needs both
  env-var defaults AND a baked config file that disables those behaviors. Env vars alone won't catch a config-driven
  knob.
- Local clone is the right primary strategy for upstream discovery work; WebFetch's summarization is too lossy for
  grep-style extraction of env var names, hardcoded URLs, and exact config-key strings.

### Follow-up Items

- **Proxy case-sensitivity gap (m14 follow-up).** Captured separately in `learnings.md`. Affects any future GitHub
  repo policy entries.
- **Verify upstream Docker image publishing.** A quick `gh api ...` check before m16.2 starts may reveal upstream
  publishes `ghcr.io/nousresearch/hermes-agent`. If they do, m16.2 may consider basing on it rather than rebuilding
  from source. Did not find evidence in the repo tree during discovery.
- **Pick a release tag for m16.2 pin.** `v2026.5.16` is current as of discovery; recommend the latest tag at the time
  m16.2 starts, not this one (will be stale).
