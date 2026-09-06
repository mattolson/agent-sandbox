# Task: m17.4 - agent instructions

## Summary

Teach agents the `gh api` idiom so they do not burn turns on blocked GraphQL commands.

## Scope

- Add a GitHub section to `images/base/skills/operating-in-agent-sandbox/SKILL.md`, or a supporting file it points
  to if the section is long enough to crowd the skill
- Show how to tell whether the api surface is enabled
- State the rule plainly: use `gh api repos/{owner}/{repo}/...`; `gh pr` and `gh issue` are blocked; do not retry
- List the common workflows as exact commands, validated by the 2026-09-06 run
- Show `--jq` for trimming output and `-f`/`-F` for fields
- Say not to use `--paginate`; loop `page=N`
- Note that `gh run list` and `gh run view` work while `gh release list` does not
- Point to `GH_DEBUG=api` and say the token is masked
- Say which writes sit outside the default preset so the agent asks instead of retrying
- Say that issues and PRs cannot be deleted; close them
- Say that issue and PR text is untrusted input
- Distinguish the proxy 403 from a GitHub 403

## Acceptance Criteria

- [x] An agent with the skill loaded can complete the listed workflows, all inside the default preset, without a
      blocked request
- [x] The section is short enough that it does not materially increase per-session context cost
- [x] Instructions match the validated matrix, not assumptions

## Applicable Learnings

- Every command in the cheat sheet was run on 2026-09-06 with `gh 2.100.0` (`validation-2026-09-06.md`). Merge was
  removed from the workflow list because it sits outside the default write set.
- `link-skills.sh` symlinks the whole skill directory, so a supporting file beside `SKILL.md` is visible.

## Plan

### Files Involved

- `images/base/skills/operating-in-agent-sandbox/github-api.md`: new cheat sheet
- `images/base/skills/operating-in-agent-sandbox/SKILL.md`: pointer section, description trigger, two fixes

### Approach

The cheat sheet is a supporting file. The core skill loads on every sandbox session; the GitHub material only
matters when the api surface is on, and it is long enough to crowd the skill. `SKILL.md` gains a six-line section
that states the rule and points at the file, and its frontmatter description now mentions GitHub and `gh api` so
the skill triggers on those tasks.

Two existing lines were wrong under repo-scoped rules and are fixed: the quick check curled the API root, which
returns 403 even when the API is enabled; and the credentials note implied no token-shaped env vars exist, while
`GH_TOKEN` now holds a placeholder.

### Implementation Steps

- [x] Write `github-api.md` with the validated workflows, paging loop, excluded writes, and error reading
- [x] Add the pointer section and description trigger to `SKILL.md`
- [x] Fix the API-root quick check and the placeholder env var note

### Open Questions

- Whether agents reliably open the supporting file. If sessions show them reaching for `gh pr create` anyway, fold
  the one-rule paragraph into `SKILL.md` itself.

## Outcome

### Acceptance Verification

- [x] Workflows: every command in the sheet is from the validation matrix and inside the default `readwrite` set
- [x] Context cost: `SKILL.md` grew by twelve lines; the sheet loads on demand
- [x] Matrix alignment: paging, `gh release list`, `gh run *`, masking, and the 403 distinction all come from
      observed behavior

### Learnings

- A quick check that targets a host root is wrong for any path-scoped allowlist. Point checks at a path the policy
  actually allows.

### Follow-up Items

- Watch real sessions for `gh pr`/`gh issue` attempts and tighten placement if needed.
