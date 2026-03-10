# Milestone: m15-proxy-secret-injection - Proxy-Side Secret Injection

## Goal

Make proxy-side secret injection the primary credential mechanism for HTTP-native auth. Real secrets stay outside the agent container and are injected by the proxy into matched outbound requests using deterministic placeholders or equivalent rule-bound markers.

## Scope

In scope:
- Host-only secret storage outside the workspace, with raw values mounted into the proxy container but not the agent container
- Proxy-side request transforms for injecting headers on matched HTTP(S) requests
- Leak-detection guardrails so placeholders or secret-targeted transforms cannot be replayed to arbitrary destinations
- One first-class supported rollout path for git over HTTPS with repo-level scoping
- Documentation that explains when this mode is sufficient and when `m17-host-credential-service` is still needed

Out of scope:
- Browser-driven or device-code OAuth flows
- Non-HTTP protocols
- Request body secret substitution
- Hosted secret managers or cloud KMS integration
- Replacing every credential flow with proxy injection

## Applicable Learnings

- Security-sensitive config should live outside the workspace and be mounted read-only.
- A host-only durable store plus a proxy-only ephemeral runtime bundle is a good baseline split for local secrets.
- Proxy-side enforcement is strongest when the proxy remains a separate sidecar the agent cannot modify.
- HTTPS path and method decisions require MITM inspection at request time, not CONNECT-time hostname checks alone.
- The current explicit proxy plus firewall design is already the right network foundation; transparent capture is not required for this feature.
- HTTP-native credentials should prefer proxy injection when possible; helper-based delivery should be a fallback, not the default.

## Tasks

### m15.1-secret-model-and-schema

**Summary:** Define the configuration model for proxy-side secrets so rules reference secret IDs, not raw secret values.

**Scope:**
- Add a design doc or decision record for secret references, supported header transforms, and match semantics.
- Define the host-only secret storage model:
  - durable host store outside the repo and bind mounts
  - per-run runtime bundle mounted read-only into the proxy only
  - no raw secrets in policy, compose, env vars, or agent-visible files
- Specify how this milestone composes with `m14-fine-grained-proxy` and when `m17-host-credential-service` is still required.
- Explicitly defer body transforms and interactive helper-based auth flows.

**Acceptance Criteria:**
- The schema clearly separates policy rules from secret values.
- The storage design specifies host paths, permission expectations, and runtime materialization behavior.
- The supported first rollout is documented as git over HTTPS with repo-level scoping.
- The plan names placeholder strategy and repo matching boundaries explicitly.

**Dependencies:** `m14-fine-grained-proxy` request-phase matcher and policy shape must be available or stable enough to target.

**Risks:** If `m14` matcher semantics change late, the secret rule shape may need rework.

### m15.2-proxy-secret-source-loading

**Summary:** Teach the proxy to load referenced secrets from a host-only source and fail safely when configuration is incomplete.

**Scope:**
- Load secrets from a proxy-only runtime bundle derived from a durable host-side store.
- Materialize the runtime bundle atomically with strict file permissions and mount it read-only into the proxy only.
- Validate required secret IDs and emit redacted diagnostics.
- Ensure the agent container does not receive the secret mount.
- Keep the first implementation simple and local:
  - durable store as a host file with strict permissions
  - optional OS keychain backend deferred
  - no remote vault dependencies

**Acceptance Criteria:**
- The proxy can resolve configured secret IDs without logging raw values.
- Missing or malformed secrets cause clear startup or reload failures.
- The durable host store lives outside the workspace and agent-visible mounts.
- The generated runtime wiring mounts only the ephemeral runtime bundle into the proxy.
- Secret updates are written atomically and can be rotated without leaking old values through logs or partial files.

**Dependencies:** `m15.1-secret-model-and-schema`

**Risks:** Host path handling and ephemeral runtime directories may differ across CLI mode and devcontainer mode.

### m15.3-request-header-injection

**Summary:** Add request-phase header injection in mitmproxy for matched HTTP(S) flows.

**Scope:**
- Inject or replace configured headers on matched host, method, and path rules.
- Reuse the request-phase inspection path from `m14-fine-grained-proxy`.
- Preserve the existing fast path for domain-only rules that do not require request mutation.
- Exclude request-body mutation and non-HTTP protocols.

**Acceptance Criteria:**
- A matched request receives the configured injected header.
- A non-matching request does not receive the injected header.
- Secret values do not appear in logs, error messages, or rendered policy output.

**Dependencies:** `m14-fine-grained-proxy`, `m15.1-secret-model-and-schema`, `m15.2-proxy-secret-source-loading`

**Risks:** Some clients may have certificate-pinning or HTTP/2 edge cases that need explicit documentation.

### m15.4-leak-detection-and-audit-logging

**Summary:** Add guardrails that block common secret leakage paths and produce useful redacted audit events.

**Scope:**
- Define deterministic placeholders or equivalent markers for supported injected-secret workflows.
- Block requests that attempt to send placeholders or secret-targeted transforms to the wrong destination.
- Add structured audit logging for injected and blocked requests with full redaction.
- Limit the first pass to request-side leak detection; full response scanning is deferred.

**Acceptance Criteria:**
- A placeholder leak attempt is blocked and logged without exposing the secret.
- Successful injected requests are logged with redacted metadata only.
- Guardrails apply only to configured secret-backed rules, not to unrelated traffic.

**Dependencies:** `m15.3-request-header-injection`

**Risks:** Placeholder matching can create false positives if the token format is too generic.

### m15.5-git-rollout-docs-and-tests

**Summary:** Ship the first end-to-end supported workflow using proxy-side secret injection, with git over HTTPS and repo-scoped credentials as the initial target.

**Scope:**
- Wire the feature into generated config or documented manual setup, whichever is simpler and safer for the first release.
- Add user docs for enabling proxy-side secret injection with git over HTTPS.
- Add regression coverage for startup validation, header injection, redacted logging, and agent-container secret isolation.
- Document the secret lifecycle clearly:
  - where durable secrets live on the host
  - how runtime bundles are materialized and cleaned up
  - why agent env vars and compose env are not used
- Validate repo-level scoping against GitHub smart-HTTP paths and Git LFS if supported.
- Document unsupported or partially supported flows clearly: browser login, device-code OAuth, and clients that require local credential state.

**Acceptance Criteria:**
- A user can `git fetch` and `git push` over HTTPS without a real token in the agent container environment.
- Repo-level scoping is documented and enforced for the supported GitHub path set.
- The docs define the baseline host storage model and mark OS keychain integration as a future hardening step, not a day-one dependency.
- The docs explain when to use this mode vs `m17-host-credential-service`.
- Tests cover the supported happy path and the main failure modes.

**Dependencies:** `m15.2-proxy-secret-source-loading`, `m15.3-request-header-injection`, `m15.4-leak-detection-and-audit-logging`

**Risks:** Devcontainer UX may need a lighter first pass than CLI mode if host secret mounting is awkward across IDEs.

## Execution Order

1. Start with `m15.1-secret-model-and-schema` to settle boundaries with `m14` and `m17`.
2. Build `m15.2-proxy-secret-source-loading` next so the runtime trust boundary is explicit before request mutation lands.
3. Implement `m15.3-request-header-injection` after the schema and secret source are stable.
4. Add `m15.4-leak-detection-and-audit-logging` immediately after injection so the first usable path already has guardrails.
5. Finish with `m15.5-git-rollout-docs-and-tests` as the first rollout.

Parallelization:
- Documentation examples can start once `m15.1` is stable.
- Follow-on evaluation of `gh` with placeholder env tokens can happen after git-over-HTTPS is stable.
- Most engineering work remains on the critical path because the injection engine depends on both matcher semantics and secret loading.

## Risks

- This feature expands the trusted role of the proxy, so unclear boundaries could lead to overreach into generic credential brokering.
- If `m14-fine-grained-proxy` slips or changes direction, this milestone stalls or needs rework.
- Some auth flows will look similar to header injection but still require OAuth callbacks, cookies, or local helper-driven credential state.
- Secret storage UX can become messy if the first version tries to solve cross-platform keychain integration too broadly.
- Runtime secret bundles can become a leakage point if creation, cleanup, or permissions are sloppy.
- GitHub path coverage is easy to get subtly wrong if Git smart-HTTP and LFS endpoints are not modeled carefully.

Mitigations:
- Keep the milestone opt-in and limited to HTTP-native credentials.
- Use a simple host-only durable file store first, with strict perms and atomic writes.
- Materialize a separate ephemeral proxy runtime bundle per run and mount it into the proxy only.
- Defer OS keychain backends to a later hardening step once the core model works.
- Roll out git over HTTPS first before widening to env-token clients such as `gh`.

## Definition of Done

- Real secret values are no longer required inside the agent container for git over HTTPS in the supported scoped path.
- Raw secret values live only in the host-side durable store and the proxy-only runtime bundle, never in the repo, compose config, agent env, or agent volume.
- The proxy can inject configured headers on matched requests while keeping raw secret values out of logs and agent-visible config.
- Secret-backed rules use explicit guardrails against obvious placeholder leakage or destination mismatch.
- Git over HTTPS with repo-level scoping is documented and tested as the first supported rollout.
- The docs clearly state that `m17-host-credential-service` remains the fallback for flows proxy injection cannot cover.

## Changes

None yet.
