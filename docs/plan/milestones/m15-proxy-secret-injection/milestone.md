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
- Add leak-detection guardrails and redacted audit logging for secret-backed requests
- Keep the injection primitive generic enough for later HTTP-native APIs and registries

## Out of Scope

- Browser or device-code OAuth flows
- Non-HTTP protocols
- Request body mutation
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
portable across storage backends: no `/`, `..`, whitespace, shell metacharacters, or platform-specific path syntax.

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
- Add leak-detection checks where practical for outbound requests and proxy responses.

## Tasks

To be broken down when work begins. Rough outline:

- Design the policy schema for secret sources and per-rule header injection
- Implement backend-neutral secret resolution with a file-backed resolver for `/run/agentbox/secrets`
- Mount `${HOME}/.config/agent-sandbox/secrets` read-only into the proxy only
- Validate secret IDs, source configuration, and secret file permissions with actionable errors or warnings
- Implement direct request header injection in the enforcer
- Support `basic` and `bearer` header transforms
- Extend the GitHub service catalog with `access` as the preferred GitHub repo-scoped capability field
- Keep `readonly` as deprecated compatibility input for unauthenticated GitHub repo-scoped entries
- Add `auth.secret` support for the `git` surface, requiring explicit `access` when `auth` is present
- Add GitHub smart-HTTP policy examples for read-only and readwrite repo scopes
- Add tests proving GitHub push endpoints can receive injected auth without credentials in the agent container
- Add guardrails for broad injection rules, existing auth headers, logs, and rendered policy output
- Update user docs for the GitHub Git flow and the limits of proxy injection

## Open Questions

- How much leak detection is practical without creating false confidence or excessive runtime cost?
- Should direct injection support response-header redaction in the first milestone?

## Definition of Done

- A repo-scoped GitHub HTTPS Git push can work without storing a GitHub token in the agent container
- Secret values are stored under `~/.config/agent-sandbox/secrets`, mounted into the proxy only, and not readable by the agent container
- Policy references logical secret IDs rather than file paths, preserving a future macOS Keychain backend path
- Explicit `domains` injection and GitHub service shorthand both render to the same rule-scoped injection model
- Rendered policy, logs, and errors show secret IDs or redacted markers only
- Injection rules are covered by unit tests and proxy enforcement tests
- Docs explain the supported GitHub Git flow, the security boundary, and unsupported auth patterns
