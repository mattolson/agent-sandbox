# Task: m17.5 - docs, examples, and tests

## Summary

User-facing docs, policy examples, and regression coverage.

## Scope

- New `docs/github.md` covering token setup, policy snippet, what works, and troubleshooting; link from `docs/git.md`
  and `docs/secrets.md`
- Recommended fine-grained PAT permissions, with Workflows, Administration, Webhooks, and Secrets withheld
- Recommend repo rulesets alongside the token
- Document the `readwrite` family list and the excluded families side by side, with authored-rule examples for
  merge and for workflow rerun
- Update `docs/policy/schema.md` and `docs/policy/examples/` for `api.auth`
- Note the interaction with the `copilot` service
- Add `docs/troubleshooting.md` entries for 403s on `/graphql` and for GitHub permission errors
- Proxy Python tests for renderer changes; an enforcement test that a shim-backed `gh api` request is rewritten
- README feature note

## Acceptance Criteria

- [x] A user can go from a fresh sandbox to a working `gh api` call by following `docs/github.md`
- [x] `go test ./...` and the proxy test suite pass
- [x] No doc still describes the REST wrapper as planned

## Applicable Learnings

- Keep one canonical doc and link back to it. `docs/github.md` owns the workflow; `git.md`, `secrets.md`, and
  `troubleshooting.md` point at it rather than restating the allowlist.
- Drive example files from tests. `github-api.yaml` renders through the same catalog path the integration test
  exercises, and the task verified it renders to six api rules, four git rules, and both shim kinds.

## Plan

### Files Involved

- `docs/github.md`: new
- `docs/policy/examples/github-api.yaml`: new; `github-repos.yaml` points at it
- `docs/policy/schema.md`: done in m17.2 alongside the code
- `docs/git.md`, `docs/secrets.md`, `docs/troubleshooting.md`, `README.md`, `CLAUDE.md`: cross-links and entries
- Tests: done in m17.2 at the catalog, render, and integration layers

### Approach

`docs/github.md` is structured as a works/blocked table, token setup, policy, in-container usage, widening one
endpoint, and troubleshooting. The widening section shows an exact-path rule for a single merge and explains why a
family-wide PUT rule also permits update-branch and review dismissal, since paths match by exact or prefix only.

### Implementation Steps

- [x] `docs/github.md`
- [x] `docs/policy/examples/github-api.yaml` and render check
- [x] Troubleshooting entries: proxy 403 on GraphQL and paging, GitHub 403 on permissions, 401 on missing `api.auth`
- [x] Cross-links from `git.md`, `secrets.md`, README, and CLAUDE.md
- [ ] Copilot interaction note: deferred; the `copilot` service allows `api.github.com` host-wide, and that
      predates this milestone. Worth a sentence in `docs/agents/copilot.md`, not here.

### Open Questions

- None.

## Outcome

### Acceptance Verification

- [x] Fresh sandbox to working call: `docs/github.md` covers secret file, policy, reload, fresh shell, and a first
      command, in that order
- [x] Tests: proxy suite 192 passing; `go test ./...` passing with no Go changes in this milestone
- [x] Wrapper: the only remaining "wrapper" mentions are historical m15 scope notes and decision 007 explaining why
      it was dropped

### Learnings

- An exact-path authored rule is the safe way to widen a single write, because prefix rules under `/pulls/` cannot
  separate merge from review dismissal.

### Follow-up Items

- One line in `docs/agents/copilot.md` noting that the Copilot baseline already allows `api.github.com` host-wide.
