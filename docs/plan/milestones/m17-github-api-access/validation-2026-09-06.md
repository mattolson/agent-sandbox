# m17 Validation: Stock `gh api` Under Repo-Scoped Rules

Date: 2026-09-06. Repo: `mattolson/agent-sandbox`. Client: `gh 2.100.0` (`linux/arm64`), downloaded and
checksum-verified inside the sandbox. Token: a fine-grained PAT scoped to this one repo, read/write on everything
except commit statuses (read). The token lived only on the host; the container held a placeholder.

## Method

No code changes. The planned `api.auth` expansion was simulated with an authored `domains` transform in
`.agent-sandbox/policy/user.agent.claude.policy.yaml`, then `agentbox proxy reload` on the host:

```yaml
domains:
  - host: api.github.com
    transform:
      request:
        headers:
          Authorization:
            secret: github.agent-sandbox.push-token
            transform:
              type: bearer
        on_existing_header: replace
    rules:
      - schemes: [https]
        path:
          exact: /repos/mattolson/agent-sandbox
      - schemes: [https]
        path:
          prefix: /repos/mattolson/agent-sandbox/
  # Download-only, for fetching the gh release tarball. Note the redirect host.
  - host: github.com
    rules:
      - schemes: [https]
        methods: [GET, HEAD]
        path:
          prefix: /cli/cli/releases/
  - host: release-assets.githubusercontent.com
    rules:
      - schemes: [https]
        methods: [GET, HEAD]
```

In the container: `GH_TOKEN=agentbox-proxy-managed`, `GH_NO_UPDATE_NOTIFIER=1`, `GH_PROMPT_DISABLED=1`, and
`GH_DEBUG=api` so every request `gh` made was logged.

## Injection proof

- With no client `Authorization` header, `X-RateLimit-Limit` came back `5000` (authenticated). Anonymous would be `60`.
- With the placeholder sent as `Authorization: token agentbox-proxy-managed`, the response was `200` with `5000`.
  `on_existing_header: replace` works as the planned shim needs.
- Every `gh api` call below returned data. The placeholder alone would have produced `401 Bad credentials`.

## Command matrix

| Command | Endpoint(s) observed | Result |
|---|---|---|
| `gh api repos/{owner}/{repo}` | `GET /repos/o/r` | OK |
| `gh api .../issues?state=all` | `GET /repos/o/r/issues` | OK |
| `gh api .../pulls?state=all` | `GET /repos/o/r/pulls` | OK |
| `gh api .../pulls/N/files`, `/reviews`, `/comments` | `GET /repos/o/r/pulls/N/...` | OK |
| `gh api .../issues/N/comments` | `GET /repos/o/r/issues/N/comments` | OK |
| `gh api .../commits/SHA/check-runs` | `GET /repos/o/r/commits/SHA/check-runs` | OK |
| `curl .../commits/SHA/statuses` | `GET /repos/o/r/commits/SHA/statuses` | OK |
| `gh api .../actions/runs` | `GET /repos/o/r/actions/runs` | OK |
| `gh api .../releases` | `GET /repos/o/r/releases` | OK |
| `gh api .../branches` | `GET /repos/o/r/branches` | OK |
| `gh api .../commits --paginate` | page 1 `/repos/o/r/commits`, page 2 `/repositories/{id}/commits` | page 2 blocked |
| `gh run list` | `GET /repos/o/r/actions/workflows`, `GET /repos/o/r/actions/runs` | OK, REST only |
| `gh release list` | `POST /graphql` | blocked |
| `gh pr list`, `gh issue list`, `gh pr checks N` | `POST /graphql` | blocked |
| `gh api graphql` | `POST /graphql` | blocked |
| `gh api user` | `GET /user` | blocked |
| `gh api search/issues?q=...` | `GET /search/issues` | blocked |
| `gh api repos/cli/cli` | `GET /repos/cli/cli` | blocked |
| `gh api -X POST .../issues` | `POST /repos/o/r/issues` | OK, created #182 |
| `gh api -X POST .../issues/182/comments` | `POST /repos/o/r/issues/182/comments` | OK |
| `gh api -X PATCH .../issues/182 -f state=closed` | `PATCH /repos/o/r/issues/182` | OK |
| `gh api -X POST .../pulls` | `POST /repos/o/r/pulls` | OK, created #183 |
| `gh api -X PATCH .../pulls/183 -f state=closed` | `PATCH /repos/o/r/pulls/183` | OK |

Every blocked request returned the proxy body `Blocked by proxy policy: api.github.com`, never a GitHub error.

## Findings

1. **`gh api` makes no hidden requests.** Across the whole run, the only requests outside `/repos/o/r` were the ones
   deliberately issued as negatives plus the pagination case below. `{owner}/{repo}` placeholders resolve from the
   local git remote with no network call.
2. **`--paginate` breaks after page one.** GitHub's `Link` header uses canonical `/repositories/{numeric-id}/...`
   URLs, which repo-scoped path rules do not match. Agents must loop `?per_page=100&page=N` explicitly, or the policy
   needs a matching `/repositories/{id}` rule. The id is not known to the renderer without the user supplying it.
3. **`gh run list` is REST-only and works. `gh release list` is GraphQL and does not.** Use
   `gh api repos/{owner}/{repo}/releases` instead.
4. **`GH_DEBUG=api` masks the token** (`Authorization: token ████`). Debug output is safe to paste into issues.
5. **No token on disk.** `gh` never wrote the placeholder anywhere under `~/.config/gh`. One run produced a
   `hosts.yml` containing only `user: mattolson`; rerunning each command in isolation did not reproduce it.
6. **Release assets redirect to `release-assets.githubusercontent.com`**, not `objects.githubusercontent.com`.
   Relevant to anyone installing `gh` from inside a sandbox; irrelevant to the image build.

## Artifacts left on the repo

- Issue #182, closed, titled "m17 validation (safe to delete)", with two comments
- PR #183, closed, from a deleted empty-commit branch, same title

## Conclusion

The approach holds. `gh api` plus proxy injection covers every repo-scoped read and write workflow in the candidate
list with the token never entering the container. The plan needs two adjustments: instruct agents to page explicitly
instead of using `--paginate`, and list `gh release list` with the GraphQL-backed commands.
