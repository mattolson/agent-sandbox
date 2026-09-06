# GitHub API Access

Agents inside the sandbox can read and write issues, pull requests, reviews, and CI status for one repository
through the GitHub REST API, using the stock `gh` CLI that ships in the base image. The token never enters the
container: the proxy injects it on each allowed request, and `gh` runs with a placeholder.

This is deliberately REST-only and repo-scoped. Stock `gh` runs most high-level commands over GraphQL, where the
repository is named in the request body rather than the URL, and the proxy does not inspect bodies. `gh api` keeps
the repository in the path, which is what the policy matches on. See
[decision 007](plan/decisions/007-stock-gh-api-over-rest-wrapper.md) for why there is no wrapper and
[decision 008](plan/decisions/008-proxy-does-not-mirror-github-permissions.md) for why the write set is fixed.

## What works

| Works | Blocked |
|---|---|
| `gh api repos/{owner}/{repo}/...` for issues, comments, pulls, reviews, check runs, workflow runs, releases | `gh pr ...`, `gh issue ...`, `gh release list`, `gh api graphql` (GraphQL) |
| Creating, editing, closing, labeling, and commenting on issues and PRs; submitting reviews | Merging, updating a PR branch, dismissing reviews, deleting comments (PUT and DELETE) |
| `gh run list`, `gh run view`, `gh run view --log-failed` | Rerunning or dispatching workflows, publishing releases |
| `curl` against the same paths | Any other repository, `/user`, `/search`, organization endpoints |

Reads are broad: everything under `/repos/{owner}/{repo}` answers to GET, including hook configurations, deploy-key
lists, and secret names. Writes are a fixed allowlist: POST and PATCH on the issues and pulls families only.
Everything else is blocked by the proxy whatever the token allows.

`--paginate` fails after the first page because GitHub's next-page links use `/repositories/{id}/...` URLs. Loop
`?per_page=100&page=N` instead. The agent skill baked into the image says so.

## Token setup

Use a fine-grained personal access token scoped to the one repository. The same secret can back both the `git` and
`api` surfaces. Recommended permissions:

- Contents: read and write (clone, fetch, push)
- Issues: read and write
- Pull requests: read and write
- Actions: read (workflow runs and logs)
- Metadata: read (implied)

Leave everything else at no access, and explicitly withhold Workflows, Administration, Webhooks, and Secrets. Without
Workflows, GitHub rejects any push that touches `.github/workflows`, which closes the CI secret-theft path. The proxy
already blocks writes to administration, webhook, key, and secret endpoints, but the token is the second layer and
should not rely on the first.

The token acts as you. Reviews the agent submits count toward approval rules on other people's pull requests, and
mentions notify real users. Pair the token with repository rulesets: require review from named humans or CODEOWNERS
on the default branch with no bypass, and protect release tags.

Store the token as a secret file on the host; see [docs/secrets.md](secrets.md):

```bash
printf '%s' "github_pat_..." \
  > "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.owner.repo.token"
chmod 600 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.owner.repo.token"
```

## Policy

Add the `api` surface to the repo-scoped GitHub entry in your user policy (`agentbox edit policy`):

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

Then apply it and open a fresh shell, since the shim exports are loaded at shell startup:

```bash
agentbox proxy reload
agentbox exec
```

`api.access: read` gives GET and HEAD only. `client_shim: {kind: env}` makes the container export
`GH_TOKEN=agentbox-proxy-managed`, so `gh` starts without a real token and the proxy overwrites the placeholder
`Authorization` header in flight. Omit `client_shim` if only `curl` will call the API; the proxy then injects the
header only when the client sends none, and fails closed if it sends one.

The full example lives at [policy/examples/github-api.yaml](policy/examples/github-api.yaml).

## Inside the container

`gh --version` prints the pinned version. `GH_TOKEN` is a placeholder; do not replace it or run `gh auth login`.

```bash
gh api 'repos/{owner}/{repo}/issues?state=open' --jq '.[] | "#\(.number) \(.title)"'
gh api -X POST 'repos/{owner}/{repo}/pulls' -f title='Title' -f head=my-branch -f base=main -f body='Body'
gh api "repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/check-runs" --jq '.check_runs[] | "\(.name): \(.conclusion)"'
```

The `{owner}` and `{repo}` placeholders are filled by `gh` from the git remote without a network call. The
`operating-in-agent-sandbox` skill in the image carries the full list of validated commands in `github-api.md`.

`GH_DEBUG=api gh api ...` logs every request. The token is masked in that output.

## Widening the default write set

Anything outside the allowlist needs an authored `domains` rule. Keep it as narrow as the task. Because rules match
paths by `exact` or `prefix` only, a family-wide rule such as PUT under `/pulls/` also allows updating branches and
dismissing reviews, not only merging. Prefer an exact path for a one-off:

```yaml
domains:
  - host: api.github.com
    transform:
      request:
        headers:
          Authorization:
            secret: github.owner.repo.token
            transform:
              type: bearer
        on_existing_header: replace
    rules:
      - schemes: [https]
        methods: [PUT]
        path:
          exact: /repos/owner/repo/pulls/45/merge
```

The same shape with `methods: [POST]` and `exact: /repos/owner/repo/actions/runs/123456/rerun` allows one CI rerun.
Remove the rule and reload when the task is done.

## Troubleshooting

- `403` with body `Blocked by proxy policy: api.github.com`: the proxy refused the path or method. Check
  `agentbox proxy logs` for the `no_rule_matched` decision line, and compare against the allowlist above.
- `403` with a GitHub JSON body such as `Resource not accessible by personal access token`: the proxy allowed it and
  the token lacks the permission. Adjust the token.
- `gh` reports `401 Bad credentials`: the placeholder reached GitHub, so injection did not run. Usually the policy
  has `api.access` but no `api.auth`, or the proxy was not reloaded.
- `GH_TOKEN` is unset in the shell: the shim exports load at shell startup. Open a new shell after the reload.

See [docs/troubleshooting.md](troubleshooting.md) for the general proxy and secret entries.
