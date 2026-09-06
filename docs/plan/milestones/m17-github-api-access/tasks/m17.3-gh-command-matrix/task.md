# Task: m17.3 - gh command matrix

## Summary

Measure which stock `gh` commands work under a repo-scoped api surface instead of guessing.

A first pass exists in `../../validation-2026-09-06.md`, run with `gh 2.100.0` against a temporary authored policy
whose write rules were a prefix catch-all. This task re-runs it against the pinned `gh` from `m17.1` and the real
`api.auth` expansion from `m17.2`, then turns the result into the documented table.

## Scope

- Run each candidate command through the proxy and record the endpoints it hits and the outcome
- Cover `gh api` variants: GET, POST, PATCH, PUT, `--paginate`, `--jq`, `--input`, and placeholders
- Re-confirm placeholder resolution stays local; document `GH_REPO` as the fallback if it changes
- Re-confirm the `--paginate` failure on `/repositories/{id}` URLs
- Cover `gh run list|view|watch`, `gh release list|view`, `gh workflow run`
- Confirm the GraphQL-backed commands fail cleanly
- Capture side requests and the env that suppresses them
- Confirm `gh` does not persist the placeholder token
- Re-run the write phase against the enumerated `readwrite` rules and add negatives for the excluded families

## Acceptance Criteria

- [x] A supported/unsupported table exists with the endpoint family each command uses
- [x] Every unsupported command has a documented `gh api` equivalent or an explicit "not possible" note
- [x] Findings feed `m17.4` and `m17.5`

## Applicable Learnings

- The first pass already answered most questions; see the validation artifact. What changed since is the write
  allowlist, so the re-run's main job is the write phase and the new negatives.
- The integration test added in `m17.2` already proves the allowlist through the real enforcer with a fake upstream.
  The re-run proves it against GitHub itself, with a real token and the real `gh` binary.

## Plan

### Files Involved

- `../../validation-2026-09-06.md`: append a second run section or add a dated sibling
- `docs/github.md`: the works/blocked table is the documented output; adjust if the re-run disagrees

### Approach

This needs the host: a rebuilt proxy image with the `m17.2` renderer, a rebuilt base image with `gh`, the real
policy from `docs/policy/examples/github-api.yaml` adapted to this repo, and the fine-grained token already on the
host. The sandbox has no Docker, so the steps below are for the host.

### Implementation Steps

- [x] `./images/build.sh base && ./images/build.sh proxy` (or `make setup` for the dev image)
- [x] Put the `api` surface with `client_shim: {kind: env}` in `.agent-sandbox/policy/user.policy.yaml` for
      `mattolson/agent-sandbox`, reusing `github.agent-sandbox.push-token`
- [x] `agentbox proxy reload`, then `agentbox up -d` so the agent container picks up the new base image and shim
- [x] In a fresh shell: `gh --version`, `echo $GH_TOKEN` (placeholder), and
      `GH_DEBUG=api gh api 'repos/{owner}/{repo}' --jq .full_name`
- [x] Read phase: the `gh api` reads from the first pass, plus `gh run list`
- [x] Write phase: create, comment on, label, and close an issue; open, review, and close a PR
- [x] Negatives against GitHub: merge, comment delete, hooks, keys, secrets, rerun, releases, refs, repo PATCH and
      DELETE, `gh pr list`, `gh api graphql`, `gh api user`, `--paginate`, and plaintext `http://` via the proxy
- [x] Confirm `~/.config/gh` holds no token; `hosts.yml` comes from linked dotfiles
- [x] Record the table; `docs/github.md` and `github-api.md` needed no changes

### Open Questions

- Whether the base image should also set `GH_REPO` from the git remote at shell start. Not needed while placeholder
  resolution stays local.

## Outcome

### Acceptance Verification

- [x] Table: second-run section in `../../validation-2026-09-06.md`, 17 read and negative checks plus the write
      phase, all as expected
- [x] Equivalents: every blocked command maps to a `gh api` call already in `github-api.md`, or is documented as
      impossible (deleting issues and PRs) or outside the default preset (merge, rerun, releases)
- [x] Fed into `m17.4` and `m17.5`: no discrepancies, no doc changes needed

### Learnings

- `curl` does not honor uppercase `HTTP_PROXY` for `http://` URLs. A plaintext probe must pass `-x` explicitly or it
  tests the firewall, not the proxy.
- A username-only `~/.config/gh/hosts.yml` can come from linked dotfiles. Check mtime against container start
  before attributing a file to the tool under test.

### Follow-up Items

- None. The amd64 image is built by CI; arm64 was verified here.
