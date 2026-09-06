# Execution Log: m17.5 - docs, examples, and tests

## 2026-09-06 - Docs written and example verified

Wrote `docs/github.md` and `docs/policy/examples/github-api.yaml`, linked from `git.md`, `secrets.md`, README, and
CLAUDE.md, and added three troubleshooting entries.

**Decision:** The "widen one endpoint" section recommends an exact path per PR or run rather than a prefix rule.
Prefix under `/pulls/` with PUT would also allow update-branch and review dismissal; the doc says so instead of
pretending the prefix form is narrow.

**Decision:** The Copilot interaction note goes in `docs/agents/copilot.md` later, not in `github.md`. The Copilot
baseline's host-wide `api.github.com` predates this milestone and is a Copilot concern.

**Learning:** Rendering the example through the integration harness's `render_authored_policy` is a two-line check
that catches a broken example before a user does. Worth doing for every example file.
