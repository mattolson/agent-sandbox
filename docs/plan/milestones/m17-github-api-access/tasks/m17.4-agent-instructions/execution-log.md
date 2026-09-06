# Execution Log: m17.4 - agent instructions

## 2026-09-06 - Cheat sheet as a supporting file

Wrote `github-api.md` beside `SKILL.md` and added a short pointer section.

**Decision:** Supporting file rather than inline. The skill loads on every session; the GitHub material is only
relevant when the api surface is enabled and is ~90 lines. `link-skills.sh` links the whole directory, so the file
is reachable.

**Issue:** The existing quick check curled `https://api.github.com` and claimed success means the API is allowed.
Under repo-scoped rules the root returns 403 even when the API is on.
**Solution:** Point the check at `/repos/OWNER/REPO` and say why.

**Issue:** The credentials note said agents will not see tokens as env vars. `GH_TOKEN` now holds a placeholder.
**Solution:** Name the placeholder and tell agents to leave it alone, so nobody tries `gh auth login` to "fix" it.
