# Task: m7.2 - Proxy Domains for Codex

## Summary

Add OpenAI service domains to the proxy enforcer so Codex can reach the OpenAI API and OAuth endpoints through the proxy.

## Scope

- Add `codex` service entry to `SERVICE_DOMAINS` in `images/proxy/addons/enforcer.py`
- Covers: OpenAI API (including regional subdomains), OAuth, ChatGPT device code flow

## Acceptance Criteria

- [x] `services: [codex]` in a policy file allows traffic to OpenAI API and OAuth endpoints
- [x] Requests to unlisted domains are still blocked

## Applicable Learnings

- Same pattern as existing services in `SERVICE_DOMAINS`. Straightforward dict entry addition.

## Plan

### Files Involved

- `images/proxy/addons/enforcer.py` (modify)

### Approach

Add a `"codex"` key to the `SERVICE_DOMAINS` dict. The milestone plan listed six domains, but analysis of `_is_allowed()` showed that `*.openai.com` already covers `api.openai.com`, `auth.openai.com`, and `console.openai.com` (the wildcard suffix `openai.com` matches both `host == suffix` and `host.endswith("." + suffix)`). This reduces the list to three entries:

- `*.openai.com` - API, OAuth, console, and regional subdomains
- `chatgpt.com` - device code OAuth flow (bare domain)
- `*.chatgpt.com` - ChatGPT subdomains

Follows the `claude` service style (wildcards only, no redundant explicit entries) rather than the `copilot` style (mixed explicit and wildcards with overlap).

### Implementation Steps

- [x] Add `codex` entry to `SERVICE_DOMAINS` in `enforcer.py`
- [x] Verify the domain list covers API and OAuth flows

### Open Questions

None.

## Outcome

### Acceptance Verification

- [x] `services: [codex]` in a policy file allows traffic to OpenAI API and OAuth endpoints - `*.openai.com` covers `api.openai.com`, `us.api.openai.com`, `auth.openai.com`, `console.openai.com`; `chatgpt.com` and `*.chatgpt.com` cover device code OAuth
- [x] Requests to unlisted domains are still blocked - no changes to enforcement logic, only added an allowlist entry

### Learnings

- The `_is_allowed` wildcard logic (`host == suffix or host.endswith("." + suffix)`) means `*.example.com` also matches the bare `example.com`. This makes separate bare domain entries unnecessary when a wildcard is present.

### Follow-up Items

None.
