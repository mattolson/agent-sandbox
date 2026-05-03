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
- Keep raw secret values in a host-only source mounted into the proxy only
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

### First rollout: GitHub smart HTTP

The first supported flow should cover GitHub git over HTTPS for a single repository. The existing `m14` GitHub `git`
surface already expands repo-scoped URL rules for:

- `/{owner}/{repo}.git/info/refs?service=git-upload-pack`
- `/{owner}/{repo}.git/git-upload-pack`
- `/{owner}/{repo}.git/info/refs?service=git-receive-pack`
- `/{owner}/{repo}.git/git-receive-pack`

Private fetch/clone needs `git-upload-pack`; push needs `git-receive-pack`. Injection must cover both discovery and
pack transfer requests for the selected access mode.

### Secret storage

Secrets should live in a host-owned source mounted into the proxy only. The policy should reference stable secret IDs,
not raw values. The rendered policy and `agentbox policy config` output must redact values.

The first implementation can require users to provide a precomputed GitHub Basic auth value, such as the base64 form of
`x-access-token:<token>`. A later task can add host-side helpers for deriving provider-specific header values from
cleaner secret inputs.

### Guardrails

- Reject or warn on injection rules that target broad wildcard hosts or host-wide catch-all paths.
- Fail closed if a request already contains the injected header, unless the rule explicitly permits replacement.
- Redact injected values in proxy logs and error messages.
- Audit successful injection by secret ID and matched rule, not by value.
- Add leak-detection checks where practical for outbound requests and proxy responses.

## Tasks

To be broken down when work begins. Rough outline:

- Design the policy schema for secret sources and per-rule header injection
- Implement proxy-side secret loading with validation and redaction
- Implement direct request header injection in the enforcer
- Add GitHub smart-HTTP policy examples for read-only and readwrite repo scopes
- Add tests proving GitHub push endpoints can receive injected auth without credentials in the agent container
- Add guardrails for broad injection rules, existing auth headers, logs, and rendered policy output
- Update user docs for the GitHub Git flow and the limits of proxy injection

## Open Questions

- Should secret values be preformatted headers at first, or should the proxy support provider-aware secret transforms?
- What exact policy shape keeps injection readable without mixing secret source config into ordinary allow rules?
- Should readwrite GitHub injection be opt-in separately from read-only clone/fetch injection?
- How much leak detection is practical without creating false confidence or excessive runtime cost?
- Should direct injection support response-header redaction in the first milestone?

## Definition of Done

- A repo-scoped GitHub HTTPS Git push can work without storing a GitHub token in the agent container
- Secret values are readable by the proxy only, not by the agent container
- Rendered policy, logs, and errors show secret IDs or redacted markers only
- Injection rules are covered by unit tests and proxy enforcement tests
- Docs explain the supported GitHub Git flow, the security boundary, and unsupported auth patterns
