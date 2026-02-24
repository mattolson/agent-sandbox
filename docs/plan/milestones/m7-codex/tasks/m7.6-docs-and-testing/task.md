# Task: m7.6 - Docs and Testing

## Summary

Document Codex agent support and clean up remaining changes from the milestone.

## Scope

- Create `docs/codex/README.md` following the Copilot doc pattern
- Update `README.md` supported agents table and agent-specific setup links
- Commit the `enforcer.py` SERVICE_DOMAINS reorder (alphabetical cleanup from m7.2)

Not in scope:
- Manual end-to-end testing (already verified: init flow, container startup, device code OAuth, proxy enforcement)

## Acceptance Criteria

- [x] `docs/codex/README.md` exists with setup, auth, usage, and network policy sections
- [x] `README.md` lists Codex in supported agents table (Preview status)
- [x] `README.md` agent-specific setup section links to Codex docs
- [ ] `enforcer.py` reorder committed

## Plan

### Files Involved

- `docs/codex/README.md` (new)
- `README.md` (modify)
- `images/proxy/addons/enforcer.py` (already modified, just needs commit)

### Approach

**docs/codex/README.md**: Mirror the Copilot doc structure (shorter than Claude since Codex is CLI-only, no IDE extension). Sections:

1. Header with one-line description and link to main README
2. Setup section with auth instructions
   - Two methods: API key (`OPENAI_API_KEY` env var) or device code OAuth (`codex login`)
   - Note that device code OAuth requires enabling in ChatGPT workspace settings (the login flow provides guidance)
3. Usage section (`codex` to start, `codex --full-auto` for auto-approve)
4. Required network policy (`services: [codex]`)

**README.md**: Two changes:
- Add `| [OpenAI Codex CLI](https://github.com/openai/codex) | Preview |` to the supported agents table
- Add `- [OpenAI Codex CLI](docs/codex/README.md)` to the agent-specific setup section

**enforcer.py**: Already reordered alphabetically. Just needs to be committed as cleanup.

### Implementation Steps

- [x] Create `docs/codex/README.md`
- [x] Update `README.md` supported agents table
- [x] Update `README.md` agent-specific setup links
- [ ] Commit enforcer.py reorder
- [ ] Commit docs changes

## Outcome

### Acceptance Verification

- [x] `docs/codex/README.md` covers setup (two auth methods), usage, and required network policy
- [x] `README.md` supported agents table includes Codex with Preview status
- [x] `README.md` agent-specific setup section links to `docs/codex/README.md`
- [ ] `enforcer.py` reorder committed (pending - git push must happen from host)

### Learnings

- Codex docs are simpler than Claude/Copilot because there is no IDE extension and no tricky auth callback flow. Device code OAuth is the cleanest auth UX of the three agents.

### Follow-up Items

None.
