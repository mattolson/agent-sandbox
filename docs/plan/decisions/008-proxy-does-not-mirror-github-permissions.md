# 008: The Proxy Does Not Mirror GitHub's Permission Model

## Status

Accepted

## Context

`m17` gives agents repo-scoped GitHub REST access through the proxy. The first draft defined `api.access: readwrite`
as any method under `/repos/{owner}/{repo}/`. A security review on 2026-09-06 showed why that is too broad: the
validation token carried Administration, Webhooks, and Secrets write, and a permission probe confirmed every admin
family under the repo prefix was reachable. A method-less prefix rule would have let the sandbox create a webhook,
which delivers events from GitHub's servers and never touches the proxy. It would also have allowed adding deploy keys
and collaborators, overwriting secrets, changing visibility, and transferring or deleting the repository.

That raised a design question: should the proxy carry a detailed model of GitHub API capabilities and expose a
configuration knob per capability, the way fine-grained tokens do?

## Decision

No. The `github` catalog keeps two access levels and owns one fixed family list.

- `read`: GET and HEAD on `/repos/{owner}/{repo}` and its prefix.
- `readwrite`: `read` plus POST on `/repos/{owner}/{repo}/issues` and `/repos/{owner}/{repo}/pulls`, and POST and
  PATCH under `/repos/{owner}/{repo}/issues/` and `/repos/{owner}/{repo}/pulls/`.

No other write method under the repo prefix is forwarded by the catalog, regardless of token permissions. That
excludes merge, update-branch, review dismissal, comment and review deletion, CI dispatch and rerun, release and ref
writes, and every write to administration, webhook, key, secret, variable, environment, pages, and repo-record
endpoints. Reads are broader: `read` forwards GET and HEAD across the whole repo prefix, so hook configurations,
deploy-key lists, and secret names stay readable. That disclosure is accepted for ergonomics and is documented in the
`m17` plan.

Users who need an excluded write author a `domains` rule for it. The catalog does not grow a per-capability surface,
and policy does not use GitHub's permission vocabulary such as `issues: write`.

## Rationale

- GitHub already enforces its own taxonomy, with knowledge of every endpoint and a maintained mapping. A proxy-side
  copy built from URL patterns would be a worse duplicate that drifts, failing either as false blocks that cost agent
  turns or as false allows that are silent holes.
- Two configuration surfaces for one concept is a burden. Users would set permissions on the token and again in
  policy, keep them consistent, and debug which layer produced a 403.
- GitHub's vocabulary in policy would imply GitHub-fidelity semantics the proxy cannot deliver. Closing an issue and
  editing its title are the same PATCH on the same path. `decisions/005` exists to keep URL matching from being
  mistaken for content-level control.
- The proxy's comparative advantage is elsewhere: keeping the secret out of the container, coarse structural scoping
  by host, repo, and method, an audit log the agent cannot erase, and a token-agnostic backstop for when token hygiene
  fails. Token hygiene does fail; the review that prompted this decision is the example.
- The rule engine is allowlist-only with `exact` and `prefix` path matching. An enumerated allowlist fits it with no
  new primitives. A prefix catch-all minus dangerous families would need deny semantics in a security-critical matcher.
- Methods draw the line in the right place. POST and PATCH cover what a coding agent does with issues and PRs. PUT and
  DELETE are where merge, dismissal, and deletion live.

Alternatives considered:

- Per-capability configuration mirroring fine-grained token permissions. Rejected for the duplication and misleading
  precision reasons above.
- Prefix catch-all with token minimization as the only guard. Rejected; it is what the review found wanting.
- A deny-list primitive in the matcher. Rejected for this milestone; it changes the security model of the engine to
  save a few authored rules.

## Consequences

**Positive:**

- The default preset cannot reconfigure the repository even with an over-privileged token. Admin families accept no
  writes from the sandbox; they remain readable under `read`.
- The list is small enough to test exhaustively and to document side by side with its exclusions.
- The `domains` escape hatch already exists, so no new authoring surface is needed for exceptions.

**Negative:**

- Legitimate workflows outside the two families fail with a proxy 403 until the user adds a rule. Known cases:
  merging, rerunning or dispatching CI, creating branches or tags through the API, and publishing releases.
- The list is opinionated. Expect requests to widen it. Each addition should be argued on what a coding agent needs,
  not on parity with GitHub's permission set.
- `readwrite` still permits closing issues and PRs and editing any comment body in the owner's name. Those are
  reversible or history-preserving on GitHub, but visible.

## Follow-up

- A third preset for maintainers, covering merge and CI rerun, may be worth adding once real usage shows the demand.
  It should be another fixed list, not a knob per capability.
- `docs/policy/schema.md` should document the `readwrite` family list and the exclusion list together, with
  authored-rule examples for the common gaps.
