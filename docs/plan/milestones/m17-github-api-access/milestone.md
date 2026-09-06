# Milestone: m17 - GitHub API Access

## Goal

Give agents repo-scoped access to the GitHub REST API from inside the sandbox using stock `gh`, so they can read
issues, pull requests, reviews, and CI status, and can open pull requests and comment, without the GitHub token ever
being readable inside the agent container.

The approach is `gh api` plus agent instructions, not a custom wrapper. `gh api` already keeps repo identity in the URL
path, which is what `m14` repo-scoped rules need, and `m15` header injection already covers the auth side. See
`decisions/007-stock-gh-api-over-rest-wrapper.md`.

## Scope

Included:

- Stock `gh` in the base image, pinned and checksum-verified for `linux/amd64` and `linux/arm64`
- `auth` support on the `api` surface of repo-scoped `github` service entries, using the existing `bearer` transform
- A fixed, catalog-owned definition of `api.access: readwrite` as POST and PATCH on the issue and pull-request
  families only. No write reaches administration, webhook, deploy-key, secret, or repo-record endpoints, whatever
  the token allows. Reads of those endpoints stay open under `read`
- A catalog-owned `GH_TOKEN` env shim so `gh` starts without a real token and the proxy replaces the placeholder
  `Authorization` header in flight
- A validated matrix of which stock `gh` commands work under a repo-scoped `api` surface and which do not
- Agent-facing instructions in the image-baked `operating-in-agent-sandbox` skill covering the `gh api` idiom and the
  most common repo workflows
- User-facing docs: token permissions, policy snippet, supported and unsupported commands, and troubleshooting
- Renderer and proxy tests for the new surface auth and shim

Excluded:

- A custom GitHub CLI or wrapper binary
- GraphQL-backed `gh` commands and `gh api graphql`; these stay blocked under repo-scoped rules
- Request-body inspection to scope GraphQL by repo; see
  `decisions/005-trust-url-matches-until-deeper-request-inspection.md`
- Endpoints outside `/repos/{owner}/{repo}`, such as `/user`, `/search`, `/orgs`, and `/notifications`
- Multi-repo or org-wide workflows
- OAuth, device-code, or `gh auth login` flows; auth is proxy-injected only
- A per-capability configuration surface that mirrors GitHub's token permission taxonomy. The catalog owns one fixed
  family list; anything outside it is an authored `domains` rule. See
  `decisions/008-proxy-does-not-mirror-github-permissions.md`
- Merge, update-branch, review dismissal, comment deletion, CI dispatch or rerun, and release or ref writes under the
  default preset. These are authored rules today and possibly a later preset

## Applicable Learnings

- Service auth semantics belong in the catalog. The api surface should reuse the same normalization, transform, and
  shim-hint path as the git surface rather than growing a second code path.
- `credential_shim` is renderer-owned and kinded (`decisions/006`). A `GH_TOKEN` shim must be paired with
  `on_existing_header: replace` on the api rules and must not be authorable as a raw env export.
- A matched URL is a trusted endpoint and bodies are not inspected (`decisions/005`). That is why GraphQL stays out.
- Go HTTP clients had HTTP/2 problems through mitmproxy, mitigated by `GODEBUG=http2client=0` in the compose stack.
  `gh` is a Go binary and inherits that env in CLI mode, but this needs verifying in devcontainer mode too.
- Keep the token narrow as well. A fine-grained PAT scoped to one repo makes GitHub a second enforcement layer. The
  proxy scopes by URL; the token scopes by repo and permission. Docs should say both.
- Validated 2026-09-06 with `gh 2.100.0` and a temporary authored policy (see `validation-2026-09-06.md`): `gh api`
  makes no hidden requests, `{owner}/{repo}` placeholders resolve locally, and `on_existing_header: replace` handles
  the placeholder token.
- GitHub `Link` pagination headers use canonical `/repositories/{id}/...` URLs, so `gh api --paginate` is blocked
  after page one under repo-scoped path rules. Agents must page explicitly.
- Token minimization is unreliable. On 2026-09-06 a token with Administration and Webhooks write, behind a method-less
  repo-prefix rule, would have let the sandbox create a webhook. Webhooks deliver from GitHub's servers and bypass the
  proxy entirely. The catalog must refuse admin families no matter what the token allows.
- The rule engine matches paths by `exact` or `prefix` only and has no deny primitive, so write scoping inside a
  family has to come from methods. POST and PATCH cover create, comment, edit, review, and close. PUT and DELETE are
  where merge, update-branch, review dismissal, and comment deletion live.

## Tasks

### m17.1-gh-in-base-image

**Summary:** Ship a pinned stock `gh` in the base image.

**Scope:**
- Install `gh` from the official release tarball for both architectures with a pinned `GH_VERSION` and checksum
  verification, following the `GIT_VERSION` pattern in `images/base/Dockerfile`
- Set `GH_NO_UPDATE_NOTIFIER=1` and `GH_PROMPT_DISABLED=1` in the image so `gh` never calls the `cli/cli` release
  endpoint or waits on a prompt
- Decide how the pin gets refreshed. Dependabot cannot see a curl download; candidates are a scheduled
  `check-gh-version.yml` in the style of the agent version checks or an entry in the dev-image bump script
- Confirm `gh` honors `HTTPS_PROXY` and the installed proxy CA, and that HTTP/2 through mitmproxy works or is disabled

**Acceptance Criteria:**
- `gh --version` in a fresh container prints the pinned version on both architectures
- `gh api` reaches the proxy and gets a policy decision, not a TLS or connection error
- No `gh` process makes a request outside the configured policy at startup

### m17.2-api-surface-auth-and-shim

**Summary:** Let a repo-scoped `github` entry inject auth on the `api` surface and export a `GH_TOKEN` placeholder.

**Scope:**
- Remove the `allow_auth=False` restriction on the `api` surface in `images/proxy/service_catalog.py`
- Keep `api.access: read` as GET and HEAD on `/repos/{owner}/{repo}` and its prefix. Reading hook configs, key lists,
  and secret names is a mild disclosure accepted for ergonomics; enumerating reads would 403 on every gap
- Define `api.access: readwrite` as `read` plus exactly these write rules, case-insensitive on the repo segment:
  - `POST /repos/{owner}/{repo}/issues`
  - `POST` and `PATCH` under `/repos/{owner}/{repo}/issues/`
  - `POST /repos/{owner}/{repo}/pulls`
  - `POST` and `PATCH` under `/repos/{owner}/{repo}/pulls/`
  That covers creating, editing, closing, labeling, and commenting on issues and PRs, and submitting reviews. It
  excludes merge and update-branch (`PUT`), review dismissal (`PUT`), comment and review deletion (`DELETE`), and
  every endpoint outside those two families
- Emit a `bearer` transform on every api rule when `api.auth.secret` is set; default to `on_existing_header: fail`
- Support `api.auth.client_shim` with a generic `env` kind whose variable name is chosen by the catalog, here
  `GH_TOKEN`. This is the primitive `m18.4` later extends to provider API keys, so keep the hint shape generic
- Switch api rules to `on_existing_header: replace` only when the shim is present
- Extend the shell-init consumer so the rendered hint exports `GH_TOKEN` with the placeholder value
- Keep the sanitized `/run/agentbox/policy.yaml` free of transforms and secret IDs, as today
- Update `docs/policy/schema.md`, which currently says `auth` is rejected on `api`
- Decide how to treat `/repositories/{id}/...` pagination URLs. Start by leaving policy alone and documenting explicit
  `page=N` loops. Add an optional numeric `id` per repo in `repos` only if `--paginate` proves necessary; the
  renderer cannot look the id up itself

Example authored policy:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.owner.repo.token
        client_shim:
          kind: git-askpass
    api:
      access: readwrite
      auth:
        secret: github.owner.repo.token
        client_shim:
          kind: env
```

**Acceptance Criteria:**
- `curl` with no `Authorization` header to `/repos/owner/repo/issues` gets the real token injected
- `gh api repos/owner/repo/issues` succeeds with only the placeholder in `GH_TOKEN`
- A request to `/repos/other/repo` or `/graphql` returns the proxy 403, not a GitHub error
- Authored top-level `credential_shim` and arbitrary env var names remain rejected
- Renderer unit tests cover read and readwrite api surfaces, with and without the shim
- Under `readwrite`: `POST .../issues`, `PATCH .../issues/N`, `POST .../pulls`, and `POST .../pulls/N/reviews` pass,
  while `PUT .../pulls/N/merge`, `DELETE .../issues/comments/ID`, `POST .../hooks`, `PATCH /repos/{owner}/{repo}`, and
  `DELETE /repos/{owner}/{repo}` return the proxy 403

### m17.3-gh-command-matrix

**Summary:** Measure which stock `gh` commands work under a repo-scoped api surface instead of guessing.

A first pass already exists in `validation-2026-09-06.md`, run with `gh 2.100.0` against a temporary authored policy.
This task re-runs it against the pinned `gh` from `m17.1` and the real `api.auth` expansion from `m17.2`, then turns
the result into the documented table.

**Scope:**
- Run each candidate command through the proxy and record the endpoints it hits and the outcome
- Cover `gh api` variants: `GET`, `POST`, `PATCH`, `PUT`, `--paginate`, `--jq`, `--input`, and `{owner}/{repo}`
  placeholders
- Re-confirm placeholder resolution stays local across `gh` versions; document `GH_REPO` as the fallback if it changes
- Re-confirm the `--paginate` failure on `/repositories/{id}` URLs and record the explicit-paging alternative
- The first pass used a prefix catch-all for writes. Re-run the write phase against the enumerated `readwrite` rules
  and add negatives for the excluded families: merge, review dismissal, comment delete, hooks, keys, secrets, and
  PATCH or DELETE on the repo record
- Cover the REST-leaning high-level commands: `gh run list|view|watch`, `gh release list|view`, `gh workflow run`
- Confirm the GraphQL-backed ones fail cleanly: `gh pr create|list|view|checks|merge`, `gh issue create|list|view`,
  `gh api graphql`
- Capture any side requests, such as update checks or `/user` lookups, and note the env or flags that suppress them
- Confirm `gh` does not persist the placeholder token to `hosts.yml` or any other file in the agent volume

**Acceptance Criteria:**
- A supported/unsupported table exists with the endpoint family each command uses
- Every unsupported command has a documented `gh api` equivalent or an explicit "not possible under repo scoping" note
- Findings feed directly into `m17.4` and `m17.5`

### m17.4-agent-instructions

**Summary:** Teach agents the `gh api` idiom so they do not burn turns on blocked GraphQL commands.

**Scope:**
- Add a GitHub section to `images/base/skills/operating-in-agent-sandbox/SKILL.md`, or a supporting file it points to
  if the section is long enough to crowd the skill
- Show how to tell whether the api surface is enabled: look for `api.github.com` in `/run/agentbox/policy.yaml`
- State the rule plainly: use `gh api repos/{owner}/{repo}/...`; high-level `gh pr` and `gh issue` commands are
  blocked; do not retry them
- List the common workflows as exact commands, validated by `m17.3`. Candidate set:
  - list and view issues
  - comment on an issue or pull request
  - create an issue
  - list and view pull requests, including files changed
  - create a pull request
  - read review comments and reviews on a pull request
  - check status and check runs for a commit
  - list workflow runs and read a failed run's log
  - view releases
- Show `--jq` for trimming output and `-f`/`-F` for fields
- Say not to use `--paginate`; loop `?per_page=100&page=N` instead, because page two lands on a blocked URL
- Note that `gh run list` and `gh run view` work, while `gh release list` does not; use the REST endpoint for releases
- Point to `GH_DEBUG=api` for troubleshooting and say the token is masked in its output
- Say which writes sit outside the default preset, such as merge, deleting comments, and rerunning CI, so the agent
  asks instead of retrying
- Say that issues and PRs cannot be deleted through the API by anyone; close them instead
- Say that issue and PR text is untrusted input from anyone who can see the repo
- Distinguish the proxy 403 (`Blocked by proxy policy`) from a GitHub 403 (token lacks permission)

**Acceptance Criteria:**
- An agent with the skill loaded can complete the listed workflows, all of which sit inside the default preset,
  without a blocked request
- The section is short enough that it does not materially increase per-session context cost
- Instructions match the validated matrix, not assumptions

### m17.5-docs-examples-and-tests

**Summary:** User-facing docs, policy examples, and regression coverage.

**Scope:**
- New `docs/github.md` covering token setup, policy snippet, what works, and troubleshooting; link from `docs/git.md`
  and `docs/secrets.md`
- Recommended fine-grained PAT permissions: Contents read/write, Pull requests read/write, Issues read/write, Actions
  read; Metadata read is implied. Explicitly no Workflows, Administration, Webhooks, or Secrets. Withholding
  Workflows makes GitHub reject pushes that touch `.github/workflows`. State that the same secret can back both
  surfaces
- Recommend repo rulesets alongside the token: a main-branch rule requiring review from named humans or CODEOWNERS
  with no bypass, and tag protection for release tags
- Document the `readwrite` family list and the excluded families side by side, with authored-rule examples for merge
  and for workflow rerun
- Update `docs/policy/schema.md` and `docs/policy/examples/` for `api.auth`
- Note the interaction with the `copilot` service, which already allows `api.github.com` host-wide
- Add a `docs/troubleshooting.md` entry for 403s on `/graphql` and for GitHub permission errors
- Proxy Python tests for renderer changes; an enforcement test that a shim-backed `gh api` request is rewritten
- README feature note if the base image gains `gh`

**Acceptance Criteria:**
- A user can go from a fresh sandbox to a working `gh api` call by following `docs/github.md`
- `go test ./...` and the proxy test suite pass
- No doc still describes the REST wrapper as planned

## Execution Order

1. `m17.1` and `m17.2` are independent and can run in parallel. `m17.2` can be validated with `curl` before `gh` exists.
2. `m17.3` needs both. Do not write instructions before the matrix exists.
3. `m17.4` and `m17.5` follow from `m17.3` and can run in parallel.

`m17.2` builds the env shim primitive in the generic shape `m18.4` describes. `m18` reuses it rather than building a
second one.

## Risks

- The GraphQL/REST split inside `gh` changes across versions, so the command matrix decays. Pin `gh`, re-run the matrix
  on bumps, and keep the instructions centered on `gh api`, which is stable.
- Agents reach for `gh pr create` by habit. The skill has to front-load the idiom, and the proxy 403 body should make
  the reason obvious.
- `on_existing_header: replace` hands the real token to any client on a matched path, including `curl` with a bogus
  header. This matches the existing git model but should be stated in docs.
- `readwrite` still allows closing issues and PRs and editing any comment body. Edits keep history on GitHub and
  closes are reversible, but both are visible actions taken in the owner's name.
- The token acts as the repo owner. Reviews the agent submits count toward approval rules on other people's PRs, and
  mentions or assignments notify real users. Rulesets should require review from named humans, not just a count.
- The family list is opinionated and will be argued about. Gaps such as creating a branch through the API or
  rerunning CI fail with a safe 403 and a documented authored-rule fix. That trade is deliberate.
- The token used for git push may lack `pull_requests` or `issues` permissions. The GitHub error is a 403 that looks
  like a proxy block to an agent. Troubleshooting must distinguish them.
- Base image size grows by the `gh` binary. Acceptable, but note it in the image docs.
- `gh` can write `~/.config/gh/hosts.yml` into the persistent agent volume. Observed once with only a username and no
  token, and not reproducible in isolation. Harmless today, but the shim must not depend on that file being absent.

## Definition of Done

- A repo-scoped policy with `api.auth` lets `gh api` read and write issues, pull requests, comments, and check status
  for one repository, with the real token never present in the agent container
- Requests to other repositories, `/graphql`, and non-repo endpoints are blocked by the proxy
- Under `readwrite`, merge, review dismissal, comment deletion, and every write to administration, webhook, key, and
  secret endpoints are blocked by the proxy regardless of token permissions. GET on those endpoints remains allowed
  under `read`, and the docs say so
- The image ships a pinned `gh`, and the `operating-in-agent-sandbox` skill documents the `gh api` idiom with validated
  commands
- The supported and unsupported command matrix is documented and reproducible
- Renderer, proxy, and Go tests pass

## Changes

### 2026-09-06: Renumbered from m18 to m17

GitHub API access ships before provider API-key injection, so the milestone numbers now match the intended order.
This milestone builds the generic env shim primitive; the provider milestone, now `m18`, reuses it.

### 2026-09-06: Narrowed `readwrite` to a fixed write allowlist

A permission probe showed the validation token carried Administration, Webhooks, and Secrets write. Combined with a
method-less repo-prefix rule, that would let a sandbox create webhooks that bypass the proxy. `readwrite` is now POST
and PATCH on the issue and pull-request families only, and the plan rejects a per-capability configuration surface.
See `decisions/008-proxy-does-not-mirror-github-permissions.md`.

### 2026-09-06: Validated the approach end to end

Simulated the planned `api.auth` expansion with an authored `domains` transform and ran stock `gh 2.100.0` against it.
Reads, writes, negatives, and injection all behaved as planned. Two adjustments came out of it: explicit paging instead
of `--paginate`, and `gh release list` joins the GraphQL-backed list. Details in `validation-2026-09-06.md`.

### 2026-09-05: Replaced the REST wrapper with stock `gh api`

The original plan proposed a Go CLI on `google/go-github`. Replaced with stock `gh`, api-surface auth injection, and
agent instructions. See `decisions/007-stock-gh-api-over-rest-wrapper.md`. Milestone directory renamed from
`m18-github-rest-wrapper` to `m18-github-api-access` (renumbered to `m17-github-api-access` the next day).
