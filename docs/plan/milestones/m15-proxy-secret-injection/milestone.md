# Milestone: m15 - Proxy Secret Injection

Make the proxy the primary credential path for HTTP-native auth by keeping real secrets out of the agent container and
injecting them into matched outbound requests.

## Problem

The current safe path for GitHub write access still pushes users toward credential material inside the agent container:
environment variables, git credential stores, command-line prompts, or tool-specific auth files. That defeats an
important part of the sandbox boundary. Network policy can restrict where traffic goes, but it cannot protect a broad
token that the agent can read directly.

`m14` already gives the proxy enough request context to identify repo-scoped Git smart-HTTP endpoints. `m15` should use
that request context to add credentials at the proxy boundary instead of asking Git or API clients inside the container
to hold the real secret.

## Goals

- Support direct matched-request credential injection for outbound HTTP headers
- Keep raw secret values in a host-only file source mounted into the proxy only
- Use backend-neutral logical secret IDs so a later macOS Keychain backend can reuse the same policy shape
- First supported rollout: GitHub git over HTTPS with repo-level scoping
- Keep GitHub tokens out of the agent container for clone, fetch, and push over smart HTTP
- Add a narrow client compatibility shim for tools that require token-shaped configuration but can operate with fake
  values
- Treat the service catalog as the owner of service auth semantics, including rule expansion, header construction, and
  compatibility hints
- Add redacted audit logging for secret-backed requests
- Keep the injection primitive generic enough for later HTTP-native APIs and registries

## Out of Scope

- Browser or device-code OAuth flows
- Non-HTTP protocols
- Request body mutation
- Request, response, header, or URL scanning for leaked secret values
- Replacing every credential flow with proxy injection
- A full host credential helper service; that remains `m18`
- macOS Keychain-backed secret resolution; m15 should preserve the extension point but ship file-backed storage first
- A complete secret-management CLI with project, target, and session scoped storage
- A new live-update control plane beyond the existing policy reload path
- GitHub REST wrapper work; that moves to `m16`

## Design

### Direct injection model

The main primitive should be direct proxy-side injection:

1. Policy matches an outbound request by host, scheme, method, path, and query.
2. The matched rule references a secret ID.
3. The proxy adds or replaces the configured HTTP header before forwarding the request.
4. Logs and rendered policy output show the secret ID, never the secret value.

The agent container should not need a fake token, placeholder password, credential store entry, or special remote URL
for the primary GitHub Git flow. Literal client-visible placeholders can remain an escape hatch for clients that cannot
be handled cleanly by direct injection, but they should not be the default design.

### Client compatibility shim

Some clients require token-shaped configuration before they start or before they choose an authenticated request path.
For those clients, m15 should support a narrow compatibility shim that provides fake, non-secret values to the agent
container while preserving proxy-side injection as the only source of real credentials.

The shim should follow these rules:

- Agent-visible values must be deterministic placeholders such as `proxy-managed`, not real secrets.
- The shim should be service-catalog-owned where possible. A service entry can imply the required agent-visible env or
  config hints, and the catalog can emit those hints alongside the rule-scoped transform metadata.
- If a client sends an auth header derived from a fake placeholder, the matching request transform rule must explicitly
  opt into `on_existing_header: replace`. The default remains `fail`.
- The primary GitHub smart-HTTP Git flow should still work through direct header injection without requiring fake
  credentials in Git config or a credential store.
- The shim is not a general placeholder-substitution system. Do not add request-body replacement, URL/query replacement,
  or secret-value scanning as part of this milestone.

This is useful for later env-token clients such as SDKs or CLIs that refuse to start without `*_API_KEY`, `GH_TOKEN`, or
similar configuration. It is a compatibility bridge, not a second credential path.

### Authoring model

m15 should support two authoring layers that compile into one internal representation:

1. A full explicit schema on `domains` entries.
2. Service-specific shorthand that expands into the same domain/rule transform representation.

For explicit `domains` entries, `transform` should be authored as a peer to `host` and `rules`. In m15, only
`transform.request.headers` is implemented. `transform.response` is reserved for future response mutation and should be
rejected if non-empty until a task explicitly implements it.

```yaml
domains:
  - host: github.com
    transform:
      request:
        headers:
          Authorization:
            secret: github.agent-sandbox.push-token
            transform:
              type: basic
              username: x-access-token
        on_existing_header: fail
    rules:
      - schemes: [https]
        methods: [GET, HEAD]
        path:
          exact: /owner/repo.git/info/refs
        query:
          exact:
            service: [git-receive-pack]
      - schemes: [https]
        methods: [POST]
        path:
          exact: /owner/repo.git/git-receive-pack
```

Although `transform` is authored at the domain entry level, rendering should associate it with that entry's emitted
rules, not with the host globally. Host-record merging must not broaden an injected credential from one authored entry
onto unrelated rules for the same host.

For GitHub service shorthand, policy authors should not need to know how to construct the full `Authorization` header.
They should provide the repo plus surface-scoped access and auth settings:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
```

The GitHub catalog can then expand this to repo-scoped smart-HTTP rules with the correct injected header construction:
`Authorization: Basic base64("x-access-token:<secret>")`.

Write-capable GitHub auth should be explicit. Prefer `git.access: read` and `git.access: readwrite` over treating the
existing `readonly: false` default as the write switch for secret-backed rules.

`git.access: read` may omit `git.auth` for public clone/fetch. `git.access: readwrite` must include `git.auth`; emitting
push-capable Git smart-HTTP rules without a proxy-side credential path is not useful for GitHub and makes the policy
claim less clear.

Surface mappings should become the preferred spelling for GitHub repo-scoped service entries generally, not only for
auth. For example, an entry that needs Git write access but API read access can say:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    git:
      access: readwrite
      auth:
        secret: github.agent-sandbox.push-token
    api:
      access: read
```

Do not support the earlier planned `surfaces` list for repo-scoped GitHub entries. It has not shipped, and the presence
of a `git` or `api` mapping is the selector. The renderer should reject `surfaces`, repo-scoped `readonly`, top-level
`access`, and top-level `auth` on repo-scoped GitHub entries. `git.auth` requires explicit `git.access`.

There is no default surface for repo-scoped GitHub entries. If `repos` is present, the entry must include at least one of
`git` or `api`; otherwise it should be rejected. If `repos` is absent, preserve the existing broad `name: github`
behavior and do not allow `git` / `api` mappings.

### Service catalog boundary

The `m14` service catalog already owns semantic expansion for services such as GitHub. m15 should deepen that boundary
instead of adding service-specific behavior to the matcher or enforcer.

For secret-backed transforms, the catalog should own:

- service-entry validation for auth-related fields
- expansion from service intent to canonical host/rule fragments
- construction of provider-specific header transforms, such as GitHub Basic auth with `x-access-token`
- selection of default `on_existing_header` behavior when a compatibility shim requires replacement
- any non-secret client compatibility hints needed by known service clients

The matcher and enforcer should remain generic. They should consume rendered rule-scoped transform metadata and optional
runtime shim metadata without knowing that a rule came from GitHub or any other service. Keep the catalog Python-backed
for m15; revisit a declarative catalog file only if more services start sharing enough structure to justify the loader
cost.

### First rollout: GitHub smart HTTP

The first supported flow should cover GitHub git over HTTPS for a single repository. The existing `m14` GitHub `git`
surface already expands repo-scoped URL rules for:

- `/{owner}/{repo}.git/info/refs?service=git-upload-pack`
- `/{owner}/{repo}.git/git-upload-pack`
- `/{owner}/{repo}.git/info/refs?service=git-receive-pack`
- `/{owner}/{repo}.git/git-receive-pack`

Private fetch/clone needs `git-upload-pack`; push needs `git-receive-pack`. Injection must cover both discovery and
pack transfer requests for the selected access mode.

### Secret references

Policy should reference stable logical secret IDs, not host file paths or raw values. Secret IDs must be path-safe and
portable across storage backends. m15 should restrict secret IDs to `[A-Za-z0-9._-]+`, which excludes `/`, `..`,
whitespace, shell metacharacters, and platform-specific path syntax.

Example policy direction:

```yaml
transform:
  request:
    headers:
      Authorization:
        secret: github.agent-sandbox.push-token
        transform:
          type: basic
          username: x-access-token
```

The proxy resolves `github.agent-sandbox.push-token` through its configured secret source, applies the transform, and
injects the resulting header. The rendered policy and `agentbox policy config` output must show only the secret ID and
redacted markers, never the resolved value.

### Secret scopes

The first file-backed implementation should not overbuild scope management, but it should avoid baking a global-only
model into policy or resolver APIs.

Useful scopes to preserve room for:

- `global`: user-wide secrets available across sandboxes, stored under the host user config directory
- `project`: secrets tied to a workspace or repo, still stored outside the workspace mount so the agent cannot read them
- `target` or `session`: secrets tied to one agent target or one running sandbox, useful for temporary credentials

Do not store project-scoped real secrets under `.agent-sandbox/` if that directory is inside the mounted workspace.
Project scoping should be implemented as a host-side lookup or overlay under `~/.config/agent-sandbox/secrets`, not as
files the agent can read through the repo mount.

m15 can ship with the global file source only, but `SecretResolver`-style APIs should accept enough context to add
project or target overlays later without changing policy syntax.

### File-backed storage

The required m15 backend is a host-owned file source rooted at `~/.config/agent-sandbox/secrets`. The directory should
be created with `0700` permissions, and individual secret files should be `0600`. Compose should mount this directory
read-only into the proxy, for example as `/run/secrets/agentbox`, and must not mount it into the agent container.

The policy should not mention `~/.config/agent-sandbox/secrets` directly. The proxy should receive a runtime secret
source configuration such as:

```text
AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox
```

The file backend maps each logical secret ID to one file below the mounted secret directory. File contents should be raw
secret values, not preformatted HTTP headers. m15 should support two generic header transforms in the first pass:
`basic` and `bearer`. Provider-specific secret derivation can come later if real use cases justify it.

### Future Keychain support

macOS Keychain support should not change policy syntax. A later implementation can reuse the same logical secret IDs by
adding another resolver backend or by having host-side `agentbox` materialize selected Keychain items into a proxy-only
runtime source before the proxy starts. Direct Keychain integration is out of scope for m15 because the proxy runs in a
Linux container and cannot read the host Keychain itself.

### Live update semantics

`m14` already added policy hot reload. m15 should build on that rather than introduce a new live-update control plane.

Expected first-pass contract:

- Policy changes that add, remove, or alter injection rules become effective through the existing proxy reload path.
- New files inside an already-mounted file secret source can be picked up without rebuilding the compose stack; the
  exact freshness contract should be defined in `m15.2` as either request-time reads or reload-aware caching.
- Removing injection from policy prevents future matching requests from receiving credentials. It cannot undo headers
  already sent on in-flight requests.
- Client compatibility shim changes that affect process environment are not hot-updatable for already-running agent
  processes. They require an agent restart, a new shell, or an explicit re-source mechanism if one is added later.

This is enough to support a future "inject during setup, remove before untrusted phase" workflow using policy reload,
but m15 should not promise a full phase-management UX unless a task explicitly implements it.

### Guardrails

- Reject or warn on injection rules that target broad wildcard hosts or host-wide catch-all paths.
- Fail closed if a request already contains the injected header, unless the rule explicitly permits replacement.
- Redact injected values in proxy logs and error messages.
- Audit successful injection by secret ID and matched rule, not by value.
- Prove with tests that the agent container cannot read the mounted secret source under the supported compose layout.
- Do not add secret-value scanning in m15. Header, URL, request-body, and response-body scanning are easy to bypass with
  encoding or alternate channels and create a broader guarantee than this milestone can honestly provide.

## Tasks

Each task should map to one reviewable PR.

### m15.1-policy-injection-schema

**Summary:** Extend the policy renderer schema so explicit `domains` entries can author request header transforms as a
peer to `host` and `rules`.

**Scope:**
- Validate `domains[].transform.request.headers` with logical secret IDs matching `[A-Za-z0-9._-]+`, `basic` and
  `bearer` transforms, and `on_existing_header`
- Reserve `domains[].transform.response` and reject non-empty response transforms until response mutation is implemented
- Render request transforms as rule-scoped metadata so host-record merging cannot broaden a credential to unrelated rules
- Define the canonical transform metadata shape and validation helpers so later service catalog auth can emit the same
  representation
- Keep rendered output redacted and free of secret values
- Add the minimum matcher loader support needed for rendered policies containing transform metadata to load safely
- Exclude file-backed secret loading, runtime request mutation, service catalog auth, and client compatibility shims

**Acceptance Criteria:**
- Renderer tests cover valid explicit request transform rules, invalid secret IDs, invalid transforms, invalid
  `on_existing_header` values, and non-empty response transform rejection
- Merge tests prove transform metadata stays attached only to the rules emitted by the authored entry
- `agentbox policy config` / rendered policy output contains secret IDs but no secret values
- The proxy matcher can load rendered rule-scoped transform metadata without applying it yet

**Dependencies:** None

**Risks:** The current canonical host-record merge path was built for allow rules. Transform metadata must not become a
host-wide side effect during dedupe or merge.

### m15.2-secret-source-and-transforms

**Summary:** Add backend-neutral secret resolution with the first file-backed resolver and generic `basic` / `bearer`
header transforms.

**Scope:**
- Resolve logical secret IDs from `AGENTBOX_SECRET_SOURCE=file:/run/secrets/agentbox`
- Map each logical secret ID to one path-safe file below the mounted secret directory
- Keep the resolver boundary context-aware enough to add project or target scoped overlays later without changing policy
  syntax
- Define whether file secret changes are visible on the next request or only after proxy reload
- Validate missing sources, missing secret files, invalid IDs, and unsafe file permissions with actionable errors or
  warnings
- Implement transform helpers for `basic` and `bearer`
- Exclude compose/scaffold changes and request injection

**Acceptance Criteria:**
- Unit tests cover successful file resolution, missing secrets, path traversal attempts, permission validation, and both
  transforms
- Secret values never appear in errors unless a test deliberately asserts internal helper behavior with redacted output
- Secret value freshness is documented and covered by a resolver test

**Dependencies:** None

**Risks:** Permission checks may behave differently across macOS bind mounts, Linux filesystems, and CI. Treat hard
failures versus warnings carefully.

### m15.3-proxy-secret-mount

**Summary:** Wire the host file-backed secret directory into the runtime so only the proxy can read it.

**Scope:**
- Mount `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` read-only into the proxy as
  `/run/secrets/agentbox`
- Set the proxy secret-source environment to the mounted file backend
- Ensure the agent service does not mount the secret directory
- Add scaffold/runtime tests for generated compose output
- Exclude request injection behavior

**Acceptance Criteria:**
- Generated CLI and devcontainer compose stacks mount the secret directory into `proxy` only
- Compose tests prove `agent` has no `/run/secrets/agentbox` or host secret-directory mount
- Missing local secret directories have clear documented behavior rather than silent Docker-created surprises

**Dependencies:** None

**Risks:** Compose variable expansion for `${HOME}` and nested defaults can be brittle. If needed, prefer an explicit
agentbox-managed env var over clever Compose syntax.

### m15.4-enforcer-header-injection

**Summary:** Inject configured headers at request time after a rule with request transform metadata matches.

**Scope:**
- Resolve referenced secrets through the configured resolver
- Apply `basic` and `bearer` transforms and set configured request headers
- Fail closed when the request already contains the injected header unless the rule explicitly permits replacement
- Emit redacted audit logs that identify the secret ID and matched rule, not the value
- Honor the freshness semantics defined by the resolver, so secret rotation behavior is predictable
- Exclude GitHub service shorthand

**Acceptance Criteria:**
- Proxy/enforcer tests prove injected headers reach a fake upstream only for matched rules
- Tests prove unmatched requests do not receive injected headers
- Existing-header behavior is covered for fail and explicit replacement modes
- Logs, errors, and rendered decisions never include the secret value

**Dependencies:** m15.1, m15.2

**Risks:** mitmproxy flow mutation must happen late enough to use the request-phase match result but early enough that
the upstream receives the header.

### m15.5-service-catalog-auth

**Summary:** Extend the service catalog boundary with surface-scoped auth-aware expansion, starting with GitHub
`git.access` and `git.auth.secret` shorthand for repo-scoped Git smart HTTP.

**Scope:**
- Keep auth semantics in the catalog and rendered rule metadata, not in the matcher or enforcer
- Add surface-scoped `git.access: read | readwrite` as the preferred GitHub Git capability field
- Add `git.auth.secret` as the GitHub Git token shorthand; do not support top-level `auth`
- Allow an optional `api.access` surface shape for repo-scoped API rules, but keep API auth out of scope for this task
- Require at least one of `git` or `api` when `repos` is present; do not infer a default repo-scoped surface
- Preserve existing broad `name: github` behavior when `repos` is absent
- Remove the unshipped repo-scoped `surfaces` field from the planned schema
- Reject `surfaces`, repo-scoped `readonly`, top-level `access`, and top-level `auth` on GitHub repo-scoped entries
- Allow `git.access: read` without `git.auth` for public clone/fetch
- Require `git.auth` when `git.access: readwrite`
- Require explicit `git.access` when `git.auth` is present
- Expand GitHub `git.auth.secret` into rule-scoped `Authorization` injection using Basic auth with username
  `x-access-token`
- Preserve a catalog extension point for service-owned compatibility hints, but do not materialize agent-visible shim
  config in this task
- Exclude non-GitHub services and GitHub REST wrapper behavior

**Acceptance Criteria:**
- Catalog and renderer tests cover `git.access: read`, `git.access: readwrite`, optional `api.access`, rejected
  `surfaces`, rejected repo-scoped `readonly`, and auth-without-access rejection
- `git.access: read` without `git.auth` remains valid and emits unauthenticated upload-pack rules
- `git.access: readwrite` without `git.auth` is rejected
- GitHub entries with `repos` but neither `git` nor `api` are rejected
- GitHub entries without `repos` preserve the existing broad service expansion and do not infer repo-scoped behavior
- Authenticated GitHub `git` service entries render the same rule-scoped transform shape as explicit `domains` entries
- Repo-scoped GitHub entries select enabled behavior through `git` and `api` mappings only
- Catalog tests prove the emitted auth metadata is canonical and does not require GitHub-specific matcher behavior

**Dependencies:** m15.1

**Risks:** This touches an existing service macro. Tests should prove unaffected simple-service behavior remains stable
while the unshipped repo-scoped `surfaces` path is removed.

### m15.6-client-compatibility-shim

**Summary:** Add a narrow agent-visible compatibility shim for service clients that need fake token-shaped setup while
real credentials stay proxy-only.

**Scope:**
- Define the rendered/runtime shape for non-secret compatibility hints emitted by the service catalog
- Materialize deterministic fake values into the agent runtime only where a service entry explicitly requires them
- Ensure shimmed clients pair with injection rules that use explicit `on_existing_header: replace` when they send a fake
  auth header
- Keep all real secret values proxy-only
- Exclude arbitrary placeholder substitution, request-body mutation, and broad client auto-detection

**Acceptance Criteria:**
- Tests prove generated agent-visible shim config contains only fake values and secret IDs, never resolved secrets
- Tests prove a shimmed header path uses explicit replacement rather than relying on the default `fail` behavior
- Existing GitHub smart-HTTP direct injection remains usable without shim config

**Dependencies:** m15.1, m15.3, m15.5

**Risks:** Client runtime configuration is not hot-updatable for already-running processes. Keep the first shim narrow and
document when an agent restart or new shell is required.

### m15.7-integration-and-boundary-tests

**Summary:** Add end-to-end coverage for the supported GitHub Git flow and the secret visibility boundary.

**Scope:**
- Use a fake upstream/proxy test to prove upload-pack and receive-pack requests receive the expected injected auth
- Prove the agent container cannot read the proxy secret mount under generated CLI and devcontainer compose layouts
- Cover read versus readwrite behavior for GitHub smart HTTP
- Cover at least one shimmed env-token style path without using a real secret in the agent-visible config
- Exclude live GitHub tests

**Acceptance Criteria:**
- Tests show private fetch/clone-style endpoints can receive auth for `git.access: read`
- Tests show push-capable receive-pack endpoints require `git.access: readwrite`
- Tests show public fetch/clone-style endpoints can be allowed by `git.access: read` without auth
- Tests fail if the agent service gains access to the secret mount
- Tests fail if compatibility shim output contains a resolved secret value

**Dependencies:** m15.3, m15.4, m15.5, m15.6

**Risks:** Full container-level boundary tests may be expensive or environment-sensitive. Use compose-config semantic
assertions where they provide the same guarantee, and reserve live-container checks for the minimum useful smoke test.

### m15.8-docs-and-examples

**Summary:** Document the m15 credential model, GitHub Git workflow, schema additions, and explicit non-goals.

**Scope:**
- Update policy schema docs for explicit `domains[].transform.request`, secret IDs, transforms, and GitHub service
  shorthand
- Add examples for read-only and readwrite GitHub Git access with file-backed secrets
- Document the client compatibility shim as fake setup values plus proxy-side replacement, not a second credential path
- Document first-pass secret scope behavior and the future project/target scope direction
- Document policy reload behavior for injection changes and the non-hot-updatable limit for process environment shims
- Document `~/.config/agent-sandbox/secrets`, expected permissions, and future Keychain-compatible secret IDs
- Document that m15 does not scan request/response content for leaked secrets
- Exclude implementation changes

**Acceptance Criteria:**
- README or CLI docs point users to the supported GitHub Git secret-injection flow
- Policy examples match renderer tests
- Docs explain the security boundary without claiming general exfiltration detection

**Dependencies:** m15.1, m15.2, m15.3, m15.5, m15.6; final examples should be checked after m15.7

**Risks:** Docs can accidentally overstate the security claim. Keep language focused on non-agent-visible credential
storage, matched injection, and redaction.

## Execution Order

Recommended sequence:

1. `m15.1-policy-injection-schema`
2. `m15.2-secret-source-and-transforms` and `m15.3-proxy-secret-mount` can proceed in parallel after the schema shape is
   stable enough to name the runtime secret source.
3. `m15.4-enforcer-header-injection` after `m15.1` and `m15.2`.
4. `m15.5-service-catalog-auth` after `m15.1`; it can proceed in parallel with `m15.4` if the rule-scoped transform IR is
   settled.
5. `m15.6-client-compatibility-shim` after the catalog auth shape and runtime mount surfaces are settled.
6. `m15.7-integration-and-boundary-tests` after `m15.3`, `m15.4`, `m15.5`, and `m15.6`.
7. `m15.8-docs-and-examples` after the schema, GitHub shorthand, and compatibility shim are stable, with final
   verification after `m15.7`.

Critical path: `m15.1 -> m15.4 -> m15.7`. The GitHub shorthand is not required for explicit domain injection to work,
but it is required for the milestone's intended user-facing workflow. The compatibility shim should not block the direct
GitHub Git path unless the chosen first shim target becomes part of the release claim.

## Open Questions

- Should m15 implement only global user secrets, or should it include project or target scoped overlays? Recommended
  default: ship global file-backed storage first, but design the resolver context so scoped overlays can be added
  without changing policy syntax.
- Should file-backed secrets be read on every matching request, cached until policy reload, or cached with file mtime
  checks? Recommended default: choose the simplest behavior that gives a clear rotation contract and does not leak
  values into logs or long-lived rendered policy.
- Should compatibility shims be inferred by known service entries, explicitly requested by policy authors, or both?
  Recommended default: infer for catalog-owned service clients only after a concrete client need exists; avoid a generic
  "set arbitrary fake env vars" feature unless tests prove it is needed.
- How much live-update UX belongs in m15 beyond existing proxy reload? Recommended default: support policy reload
  semantics only, and document that already-running agent process environments cannot be updated in place.

## Definition of Done

- A repo-scoped GitHub HTTPS Git push can work without storing a GitHub token in the agent container
- Secret values are stored under `~/.config/agent-sandbox/secrets`, mounted into the proxy only, and not readable by the agent container
- Policy references logical secret IDs rather than file paths, preserving a future macOS Keychain backend path
- Explicit `domains` request transforms and service catalog auth shorthand both render to the same rule-scoped transform
  model
- At least one compatibility-shim path can provide fake agent-visible setup values while the proxy injects the real
  credential
- Rendered policy, logs, and errors show secret IDs or redacted markers only
- Injection rules are covered by unit tests and proxy enforcement tests
- Docs explain the supported GitHub Git flow, the security boundary, and unsupported auth patterns

## Changes

### 2026-05-03: Added compatibility shim, catalog-auth boundary, and live-update/scoping exploration

Competitor research showed three useful prior-art patterns: service catalogs that own auth expansion, fake client-visible
setup values paired with proxy-side real credential injection, and live policy updates. The milestone now includes a
separate client compatibility shim task, expands the service catalog as the owner of service auth semantics, preserves
room for future scoped secret storage, and limits m15 live updates to the existing policy reload path unless a later task
intentionally widens that contract.

### 2026-05-09: Switched GitHub auth shorthand to surface-scoped access

The original m15.5 shorthand put `access` and `auth` beside `surfaces`, which made `auth` ambiguous when one entry
covered both Git and API surfaces. The plan now prefers `git.access` plus `git.auth.secret`, allows optional
`api.access`, and rejects top-level `auth`.

### 2026-05-09: Removed unshipped `surfaces` syntax from M15.5

Because repo-scoped GitHub `surfaces` has not shipped, the plan no longer carries it as deprecated compatibility input.
The presence of `git` or `api` mappings selects the enabled behavior. Repo-scoped `surfaces`, `readonly`, top-level
`access`, and top-level `auth` should be rejected.

### 2026-05-09: Clarified Git read auth optionality and write auth requirement

`git.access: read` may omit `git.auth` for public clone/fetch. `git.access: readwrite` must include `git.auth` because
push-capable GitHub smart-HTTP rules without credentials are not useful and make the policy claim ambiguous.

### 2026-05-09: Rejected repo-scoped GitHub defaults

Repo-scoped GitHub entries do not infer a default surface. `repos` must be paired with at least one of `git` or `api`.
When `repos` is absent, the existing broad `name: github` service behavior remains the default.
