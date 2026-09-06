# 007: Use Stock `gh api` Instead Of A Custom GitHub REST Wrapper

## Status

Accepted

## Context

`m18` originally planned a Go CLI on `google/go-github` that would expose a curated set of repo-scoped GitHub
workflows over REST only. The motivation is sound: stock `gh` runs most high-level commands over GraphQL, where the
repo lives in the request body, and `decisions/005` says the proxy trusts a matched URL and does not inspect bodies.
Repo-scoped `m14` rules therefore cannot constrain GraphQL to one repository.

While reviewing sandbox GitHub access on 2026-09-05, two things changed the calculus:

- `gh api` already is a REST-only client with repo identity in the URL path. It supports `{owner}/{repo}`
  placeholders, `--jq`, `--paginate`, and typed fields, and agents know it well.
- The `m15` injection layer already supports `bearer` transforms and the renderer-owned shim model, and the `m17` plan
  already describes a generic env shim primitive. A `GH_TOKEN` shim is the same primitive with a different variable
  name.

The remaining gap is small: allow `auth` on the `api` surface, add the shim, install `gh`, and tell agents which idiom
to use.

## Decision

Drop the custom wrapper. `m18` becomes:

- Stock `gh` in the base image, pinned
- `api.auth` on repo-scoped `github` service entries, with a catalog-owned `GH_TOKEN` shim
- A validated matrix of which stock `gh` commands work under repo-scoped rules
- Agent instructions in the `operating-in-agent-sandbox` skill that lead with `gh api repos/{owner}/{repo}/...`

The milestone directory is renamed from `m18-github-rest-wrapper` to `m18-github-api-access`.

## Rationale

- `gh api` gives the wrapper's core property, URL-visible repo identity, with no new code to maintain.
- A bespoke CLI is a second product. The original plan already anticipated it might need to be spun out. That is a
  signal the scope was wrong for this repo.
- Agents already have `gh` and REST routes in their training. A new command surface would need to be learned from
  docs on every session, which costs context and turns.
- The proxy stays the enforcer for URL scope. Pairing it with a fine-grained PAT scoped to the same repo gives two
  independent layers: the proxy bounds the URL surface, GitHub bounds the repo and permissions.
- If `gh api` friction proves real, a thin wrapper can still be added later on top of this work. Nothing here is lost.

Alternatives considered:

- Allow `api.github.com` host-wide and rely on the fine-grained PAT alone. Stock `gh` would work fully, including
  GraphQL. Rejected as the default because the proxy would no longer independently scope API traffic, which cuts
  against `decisions/001`. Users who accept that tradeoff can still author it.
- Inspect GraphQL bodies to extract the repo. Rejected; queries can reference repos by node ID and shapes vary by `gh`
  version. This is exactly what `decisions/005` deferred.
- Keep the wrapper plan. Rejected for the cost reasons above.

## Consequences

**Positive:**

- No new binary, release pipeline, or command surface to maintain
- Reuses `m14` rules, `m15` injection, and the `m17` shim shape
- Repo scoping is enforced at the proxy and can be tightened further with authored rules

**Negative:**

- High-level `gh pr` and `gh issue` commands fail with a proxy 403 under repo-scoped rules. Agents must use `gh api`
  and need instructions that say so.
- The supported command matrix depends on `gh` internals and must be re-validated when the pin changes.
- Workflows that need non-repo endpoints (`/user`, `/search`, org-level) stay unsupported under repo scoping.
