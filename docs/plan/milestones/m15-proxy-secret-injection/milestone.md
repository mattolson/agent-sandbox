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

### Authoring model

m15 should support two authoring layers that compile into one internal representation:

1. A full explicit schema on `domains` entries.
2. Service-specific shorthand that expands into the same domain/rule/injection representation.

For explicit `domains` entries, `inject` should be authored as a peer to `host` and `rules`:

```yaml
domains:
  - host: github.com
    inject:
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

Although `inject` is authored at the domain entry level, rendering should associate it with that entry's emitted rules,
not with the host globally. Host-record merging must not broaden an injected credential from one authored entry onto
unrelated rules for the same host.

For GitHub service shorthand, policy authors should not need to know how to construct the full `Authorization` header.
They should provide the repo, surface, access level, and logical secret reference:

```yaml
services:
  - name: github
    repos:
      - owner/repo
    surfaces: [git]
    access: readwrite
    auth:
      secret: github.agent-sandbox.push-token
```

The GitHub catalog can then expand this to repo-scoped smart-HTTP rules with the correct injected header construction:
`Authorization: Basic base64("x-access-token:<secret>")`.

Write-capable GitHub auth should be explicit. Prefer `access: read` and `access: readwrite` over treating the existing
`readonly: false` default as the write switch for secret-backed rules.

`access` should become the preferred spelling for GitHub repo-scoped service entries generally, not only for auth.
`readonly` should remain as deprecated compatibility input for existing unauthenticated policies. The renderer should
reject entries that specify both `access` and `readonly`, normalize `readonly: true` to `access: read`, and normalize
`readonly: false` to `access: readwrite`. When `auth` is present, `access` must be explicit and `readonly` should be
rejected.

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
inject:
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

### File-backed storage

The required m15 backend is a host-owned file source rooted at `~/.config/agent-sandbox/secrets`. The directory should
be created with `0700` permissions, and individual secret files should be `0600`. Compose should mount this directory
read-only into the proxy, for example as `/run/agentbox/secrets`, and must not mount it into the agent container.

The policy should not mention `~/.config/agent-sandbox/secrets` directly. The proxy should receive a runtime secret
source configuration such as:

```text
AGENTBOX_SECRET_SOURCE=file:/run/agentbox/secrets
```

The file backend maps each logical secret ID to one file below the mounted secret directory. File contents should be raw
secret values, not preformatted HTTP headers. m15 should support two generic header transforms in the first pass:
`basic` and `bearer`. Provider-specific secret derivation can come later if real use cases justify it.

### Future Keychain support

macOS Keychain support should not change policy syntax. A later implementation can reuse the same logical secret IDs by
adding another resolver backend or by having host-side `agentbox` materialize selected Keychain items into a proxy-only
runtime source before the proxy starts. Direct Keychain integration is out of scope for m15 because the proxy runs in a
Linux container and cannot read the host Keychain itself.

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

**Summary:** Extend the policy renderer schema so explicit `domains` entries can author `inject` as a peer to `host` and
`rules`.

**Scope:**
- Validate `domains[].inject.headers` with logical secret IDs matching `[A-Za-z0-9._-]+`, `basic` and `bearer`
  transforms, and `on_existing_header`
- Render injection as rule-scoped metadata so host-record merging cannot broaden an injected credential to unrelated
  rules
- Keep rendered output redacted and free of secret values
- Exclude file-backed secret loading and runtime request mutation

**Acceptance Criteria:**
- Renderer tests cover valid explicit injection rules, invalid secret IDs, invalid transforms, and invalid
  `on_existing_header` values
- Merge tests prove injected metadata stays attached only to the rules emitted by the authored entry
- `agentbox policy config` / rendered policy output contains secret IDs but no secret values

**Dependencies:** None

**Risks:** The current canonical host-record merge path was built for allow rules. Injection metadata must not become a
host-wide side effect during dedupe or merge.

### m15.2-secret-source-and-transforms

**Summary:** Add backend-neutral secret resolution with the first file-backed resolver and generic `basic` / `bearer`
header transforms.

**Scope:**
- Resolve logical secret IDs from `AGENTBOX_SECRET_SOURCE=file:/run/agentbox/secrets`
- Map each logical secret ID to one path-safe file below the mounted secret directory
- Validate missing sources, missing secret files, invalid IDs, and unsafe file permissions with actionable errors or
  warnings
- Implement transform helpers for `basic` and `bearer`
- Exclude compose/scaffold changes and request injection

**Acceptance Criteria:**
- Unit tests cover successful file resolution, missing secrets, path traversal attempts, permission validation, and both
  transforms
- Secret values never appear in errors unless a test deliberately asserts internal helper behavior with redacted output

**Dependencies:** None

**Risks:** Permission checks may behave differently across macOS bind mounts, Linux filesystems, and CI. Treat hard
failures versus warnings carefully.

### m15.3-proxy-secret-mount

**Summary:** Wire the host file-backed secret directory into the runtime so only the proxy can read it.

**Scope:**
- Mount `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` read-only into the proxy as
  `/run/agentbox/secrets`
- Set the proxy secret-source environment to the mounted file backend
- Ensure the agent service does not mount the secret directory
- Add scaffold/runtime tests for generated compose output
- Exclude request injection behavior

**Acceptance Criteria:**
- Generated CLI and devcontainer compose stacks mount the secret directory into `proxy` only
- Compose tests prove `agent` has no `/run/agentbox/secrets` or host secret-directory mount
- Missing local secret directories have clear documented behavior rather than silent Docker-created surprises

**Dependencies:** None

**Risks:** Compose variable expansion for `${HOME}` and nested defaults can be brittle. If needed, prefer an explicit
agentbox-managed env var over clever Compose syntax.

### m15.4-enforcer-header-injection

**Summary:** Inject configured headers at request time after a rule with injection metadata matches.

**Scope:**
- Resolve referenced secrets through the configured resolver
- Apply `basic` and `bearer` transforms and set configured request headers
- Fail closed when the request already contains the injected header unless the rule explicitly permits replacement
- Emit redacted audit logs that identify the secret ID and matched rule, not the value
- Exclude GitHub service shorthand

**Acceptance Criteria:**
- Proxy/enforcer tests prove injected headers reach a fake upstream only for matched rules
- Tests prove unmatched requests do not receive injected headers
- Existing-header behavior is covered for fail and explicit replacement modes
- Logs, errors, and rendered decisions never include the secret value

**Dependencies:** m15.1, m15.2

**Risks:** mitmproxy flow mutation must happen late enough to use the request-phase match result but early enough that
the upstream receives the header.

### m15.5-github-service-auth

**Summary:** Extend the GitHub service catalog with `access` and `auth.secret` shorthand for repo-scoped Git smart HTTP.

**Scope:**
- Add `access: read | readwrite` as the preferred GitHub repo-scoped capability field
- Keep `readonly` as deprecated compatibility input for unauthenticated GitHub repo-scoped entries
- Reject entries that specify both `access` and `readonly`
- Require explicit `access` when `auth` is present, and reject `auth` with deprecated `readonly`
- Expand GitHub `auth.secret` into rule-scoped `Authorization` injection using Basic auth with username
  `x-access-token`
- Exclude non-GitHub services and GitHub REST wrapper behavior

**Acceptance Criteria:**
- Catalog and renderer tests cover `access: read`, `access: readwrite`, deprecated `readonly`, mixed-field rejection,
  and auth-without-access rejection
- Authenticated GitHub `git` service entries render the same rule-scoped injection shape as explicit `domains` entries
- Existing unauthenticated `readonly` policies remain valid

**Dependencies:** m15.1

**Risks:** This touches an existing service macro. Compatibility tests should cover current `readonly` behavior before
adding the new spelling.

### m15.6-integration-and-boundary-tests

**Summary:** Add end-to-end coverage for the supported GitHub Git flow and the secret visibility boundary.

**Scope:**
- Use a fake upstream/proxy test to prove upload-pack and receive-pack requests receive the expected injected auth
- Prove the agent container cannot read the proxy secret mount under generated CLI and devcontainer compose layouts
- Cover read versus readwrite behavior for GitHub smart HTTP
- Exclude live GitHub tests

**Acceptance Criteria:**
- Tests show private fetch/clone-style endpoints can receive auth for `access: read`
- Tests show push-capable receive-pack endpoints require `access: readwrite`
- Tests fail if the agent service gains access to the secret mount

**Dependencies:** m15.3, m15.4, m15.5

**Risks:** Full container-level boundary tests may be expensive or environment-sensitive. Use compose-config semantic
assertions where they provide the same guarantee, and reserve live-container checks for the minimum useful smoke test.

### m15.7-docs-and-examples

**Summary:** Document the m15 credential model, GitHub Git workflow, schema additions, and explicit non-goals.

**Scope:**
- Update policy schema docs for explicit `domains[].inject`, secret IDs, transforms, and GitHub service shorthand
- Add examples for read-only and readwrite GitHub Git access with file-backed secrets
- Document `~/.config/agent-sandbox/secrets`, expected permissions, and future Keychain-compatible secret IDs
- Document that m15 does not scan request/response content for leaked secrets
- Exclude implementation changes

**Acceptance Criteria:**
- README or CLI docs point users to the supported GitHub Git secret-injection flow
- Policy examples match renderer tests
- Docs explain the security boundary without claiming general exfiltration detection

**Dependencies:** m15.1, m15.2, m15.3, m15.5; final examples should be checked after m15.6

**Risks:** Docs can accidentally overstate the security claim. Keep language focused on non-agent-visible credential
storage, matched injection, and redaction.

## Execution Order

Recommended sequence:

1. `m15.1-policy-injection-schema`
2. `m15.2-secret-source-and-transforms` and `m15.3-proxy-secret-mount` can proceed in parallel after the schema shape is
   stable enough to name the runtime secret source.
3. `m15.4-enforcer-header-injection` after `m15.1` and `m15.2`.
4. `m15.5-github-service-auth` after `m15.1`; it can proceed in parallel with `m15.4` if the rule-scoped injection IR is
   settled.
5. `m15.6-integration-and-boundary-tests` after `m15.3`, `m15.4`, and `m15.5`.
6. `m15.7-docs-and-examples` after the schema and GitHub shorthand are stable, with final verification after `m15.6`.

Critical path: `m15.1 -> m15.4 -> m15.6`. The GitHub shorthand is not required for explicit domain injection to work,
but it is required for the milestone's intended user-facing workflow.

## Open Questions

(None currently)

## Definition of Done

- A repo-scoped GitHub HTTPS Git push can work without storing a GitHub token in the agent container
- Secret values are stored under `~/.config/agent-sandbox/secrets`, mounted into the proxy only, and not readable by the agent container
- Policy references logical secret IDs rather than file paths, preserving a future macOS Keychain backend path
- Explicit `domains` injection and GitHub service shorthand both render to the same rule-scoped injection model
- Rendered policy, logs, and errors show secret IDs or redacted markers only
- Injection rules are covered by unit tests and proxy enforcement tests
- Docs explain the supported GitHub Git flow, the security boundary, and unsupported auth patterns
