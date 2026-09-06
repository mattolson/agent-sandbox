# What's New In m17: GitHub API Access Through `gh api`

`m17` lets an agent inside the sandbox read and write issues, pull requests, reviews, and CI status for one
repository through the GitHub REST API, using the stock `gh` CLI that now ships in the base image. The token stays
on the host; the proxy injects it, and `gh` runs with a placeholder. See [docs/github.md](../github.md) for the
workflow.

Most existing policies are unaffected. Two behaviors did change for policies that already used the GitHub `api`
surface or authored request transforms, and they are called out below.

## What you get

- **`gh` in the base image.** Pinned and checksum-verified per architecture. `GH_NO_UPDATE_NOTIFIER` and
  `GH_PROMPT_DISABLED` are set so it never phones home for updates or blocks on a prompt.
- **`api.auth` on repo-scoped GitHub entries.** Previously reserved and rejected. It now attaches
  `Authorization: Bearer <secret>` to every emitted api rule, the same way `git.auth` attaches Basic auth.
- **An `env` client shim.** `api.auth.client_shim: {kind: env}` exports `GH_TOKEN=agentbox-proxy-managed` into
  the agent shell and switches the api rules to `on_existing_header: replace`, so `gh` starts without a real token
  and the proxy overwrites the placeholder in flight.
- **Agent instructions.** The `operating-in-agent-sandbox` skill gains a `github-api.md` cheat sheet with the
  validated `gh api` commands, explicit paging, and what stays blocked.

## Behavior changes

### `api.access: readwrite` is now a fixed write allowlist

Before `m17`, `readwrite` on the `api` surface meant any method on `/repos/{owner}/{repo}` and everything under it,
which forwarded every write GitHub offers, including webhooks, deploy keys, secrets, collaborators, and the repository
record itself. It now means the GET and HEAD read rules plus:

- `POST /repos/{owner}/{repo}/issues` and `POST /repos/{owner}/{repo}/pulls`
- `POST` and `PATCH` under `/repos/{owner}/{repo}/issues/` and `/repos/{owner}/{repo}/pulls/`

Merge, update-branch, and review dismissal (`PUT`), comment and review deletion (`DELETE`), and every family outside
issues and pulls are blocked by the proxy regardless of what the token allows. Reads are unchanged and remain broad.
The reasoning is in [decision 008](../plan/decisions/008-proxy-does-not-mirror-github-permissions.md).

**What to do:** nothing, unless an agent or script relied on one of the excluded writes. For those, author a
`domains` rule for the exact path you need; [docs/github.md](../github.md#widening-the-default-write-set) shows the
shape for a single merge or a single CI rerun.

### Rules that carry a credential transform are https-only

Any rule the renderer attaches a request transform to, whether from the GitHub catalog (`git.auth`, `api.auth`) or
from an authored `domains[].transform`, now permits only `https`. Previously such rules inherited `http` too, which
would have let a plaintext request through the proxy with the real credential injected.

**What to do:** nothing for catalog entries. For an authored transform rule that listed `schemes: [http, https]`,
`http` is dropped silently. A rule that listed only `http` together with a transform now fails rendering with a
message that says so; change it to `https`.

## Getting the new images

`gh` and the env shim live in the base and proxy images. Pull them and recreate the containers:

```bash
agentbox bump
agentbox up -d
```

Then add the `api` surface to your policy as described in [docs/github.md](../github.md), reload with
`agentbox proxy reload`, and open a fresh shell. The `GH_TOKEN` export is loaded at shell startup, so an agent
process started before the reload will not see it.

## Backward compatibility

- Policies without an `api` surface render exactly as before, apart from the git rules dropping `http`, which git
  over HTTPS never used.
- `api.access: read` is unchanged.
- The rendered `credential_shim` payload keeps `version: 1`; existing git-askpass hints are unchanged and the new
  env hints sit beside them.
