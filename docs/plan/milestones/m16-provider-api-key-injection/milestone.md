# Milestone: m16 - Provider API-Key Injection

## Goal

Extend the `m15` proxy-side credential model from GitHub Git auth to model-provider API-key traffic, so supported agents
can call OpenAI, Anthropic, and Gemini-style APIs without the real API key being readable inside the agent container.

This milestone should make provider API-key injection a first-class, documented path for current agents that support
API-key auth, while keeping OAuth, device-code, and local credential-helper flows out of this layer.

## Scope

Included:

- Provider API-key injection for OpenAI, Anthropic, and Gemini API request patterns
- A generic raw-header secret transform for headers whose value is the secret itself
- Service-catalog-owned provider auth expansion, rather than hand-authored request transforms in examples
- A generic renderer-owned env-var shim primitive for catalog-owned client compatibility hints, first used for
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GEMINI_API_KEY`
- Integration coverage for Codex, Claude API-key mode, Gemini API-key mode, and provider-backed Pi/OpenCode flows where
  they use supported providers
- Documentation and examples that distinguish proxy-injected API-key flows from OAuth/login flows

Excluded:

- Copilot and Factory primary auth, unless a concrete API-key flow is identified during discovery
- OAuth, browser login, device-code, refresh-token, and subscription-login flows
- Request-body mutation, response mutation, or scanning for leaked secret values
- Local delivery of real credentials into the agent container; residual cases stay with `m19-host-credential-service`
- Arbitrary user-authored env exports that are not paired with catalog-owned proxy replacement rules
- Clients that copy env credentials into query strings, request bodies, signatures, or local auth stores in a way the
  proxy cannot safely replace
- Broad provider abstraction across every Models.dev or AI SDK provider
- A full `agentbox secrets` management CLI

## Applicable Learnings

- Service auth semantics belong in the catalog, not the matcher or enforcer. The matcher should continue consuming
  canonical host/rule/transform IR.
- Request transforms must force request inspection at CONNECT time for HTTPS, even when no method/path/query rule is
  otherwise required.
- Header injection should stage all rendered values before mutating a request, so failures block cleanly without partial
  mutation.
- Renderer-owned shim metadata is the right boundary when an agent-visible fake credential must be paired with proxy
  replacement rules.
- A generic compatibility primitive is useful, but it must not become a generic authoring escape hatch. Known catalog
  entries should request the shim and the matching replacement rules together.
- User-facing examples should be backed by integration tests so documented policy shapes do not drift from renderer
  behavior.
- Proxy-side injection does not protect a secret that the user also stores in an agent volume, env var, project file, or
  provider-specific auth file.

## Tasks

### m16.1-provider-auth-discovery-and-schema

**Summary:** Confirm provider request shapes and define the authored service schema for API-key injection.

**Scope:**
- Verify the current auth headers and env-var conventions for OpenAI, Anthropic, and Gemini
- Identify which current agents can plausibly use provider API-key mode through env vars or config
- Decide the rich service authoring shape for provider auth, including `auth.secret` and optional `client_shim`
- Define the generic rendered env-shim IR separately from the service-specific authored shape
- Decide whether Gemini supports only `GEMINI_API_KEY` first, or also `GOOGLE_API_KEY`
- Exclude OAuth/login flows from the schema

**Acceptance Criteria:**
- The milestone has a concrete YAML authoring shape for each supported provider service
- The rendered env-shim shape can support future catalog-owned env-token clients without exposing arbitrary env exports
- Unsupported auth modes are documented explicitly
- The design names which supported agents are expected to work in the first rollout

**Dependencies:** m15 proxy-side secret injection

**Risks:** Agent CLIs may validate API-key formats before making network requests, which could make a simple fake env var
insufficient for some clients.

### m16.2-raw-header-transform

**Summary:** Add a generic transform that injects the resolved secret as the complete header value.

**Scope:**
- Add a `raw` request-header transform alongside existing `bearer` and `basic`
- Preserve existing validation and redaction behavior
- Keep `on_existing_header: fail` as the default
- Add unit and integration coverage for raw header injection and failure paths

**Acceptance Criteria:**
- A policy rule can inject `x-api-key: <secret>` or `x-goog-api-key: <secret>` without custom provider code in the
  enforcer
- Logs show secret IDs and transform type but never resolved values
- Existing `bearer` and `basic` tests continue to pass

**Dependencies:** None beyond m15

**Risks:** A too-specific transform name could leak provider assumptions into the generic injection layer. Keep this
strictly header-value-oriented.

### m16.3-provider-service-catalog-auth

**Summary:** Teach the service catalog to emit provider-specific request rules and header transforms.

**Scope:**
- Add rich auth mappings for the existing `claude`, `codex`, and `gemini` services
- Emit `Authorization: Bearer <secret>` for OpenAI-compatible API calls
- Emit `x-api-key: <secret>` for Anthropic API calls
- Emit `x-goog-api-key: <secret>` for Gemini API calls
- Keep broad host-only service entries backward-compatible when no auth mapping is present
- Keep provider semantics in `service_catalog.py`; do not add provider branches to the matcher or enforcer

**Acceptance Criteria:**
- Authenticated provider service entries render into canonical host records with rule-scoped transforms
- Unauthenticated service entries preserve current behavior
- Renderer tests reject unsupported auth keys and malformed secret IDs

**Dependencies:** `m16.1`, `m16.2`

**Risks:** Existing simple service names have broad host expansion. Adding auth must not accidentally inject credentials
into unrelated login, telemetry, documentation, or update hosts.

### m16.4-generic-env-credential-shim

**Summary:** Build a generic renderer-owned env-var shim primitive and wire provider API-key uses through the catalog.

**Scope:**
- Extend rendered shim metadata beyond Git askpass while keeping it renderer-owned and kinded
- Support a generic `env` shim kind that can emit deterministic fake env values for catalog-selected variable names
- Pair each env shim emission with `on_existing_header: replace` on the matching provider rules
- Keep authored policy service-specific, for example `auth.client_shim.kind: env`, rather than letting users provide
  arbitrary env var names
- Source the generated env exports through the existing shell init path
- Keep the primitive reusable for later catalog-owned env-token clients that map fake env values to replaceable request
  headers

**Acceptance Criteria:**
- A service entry can opt into a known env shim without exposing the real secret
- The proxy replaces a fake client-generated auth header with the real header before upstream delivery
- Authored policy cannot name arbitrary env vars or emit env shims without matching proxy replacement rules
- The rendered shim metadata is generic enough to cover future catalog-owned env-token clients without changing the
  shell-init consumer contract
- Authored top-level shim metadata remains rejected

**Dependencies:** `m16.3`

**Risks:** Some clients may inspect key prefixes, copy the fake value into a query string or request body, or use the env
value to sign requests before making a replaceable HTTP request. Those clients may need a provider-specific shim or may
remain out of scope.

### m16.5-agent-flow-integration

**Summary:** Wire and document the supported first-rollout agent flows.

**Scope:**
- Validate the flow for Codex with OpenAI API-key auth
- Validate the flow for Claude Code API-key mode when using Anthropic API credentials
- Validate the flow for Gemini CLI API-key mode
- Validate provider-backed Pi and OpenCode flows where they use OpenAI, Anthropic, or Gemini
- Document that Copilot and Factory remain OAuth/login-based unless a supported API-key path is found

**Acceptance Criteria:**
- Each supported flow has a policy example and setup notes
- Each unsupported flow has a clear explanation instead of a silent omission
- Agent docs no longer recommend putting real supported provider API keys inside the container as the primary path

**Dependencies:** `m16.4`

**Risks:** Live-provider validation can be hard to run in CI. Prefer mocked proxy integration tests plus documented manual
smoke checks.

### m16.6-docs-examples-and-tests

**Summary:** Add end-user docs, policy examples, and regression coverage for the full provider API-key injection path.

**Scope:**
- Update `docs/secrets.md`, `docs/policy/schema.md`, agent docs, README, and troubleshooting guidance
- Add examples for OpenAI, Anthropic, and Gemini provider auth
- Add integration tests that prove fake env-derived headers are replaced and real secrets are redacted
- Add failure-mode tests for missing secrets, existing headers, unsupported auth shapes, and unsafe secret permissions

**Acceptance Criteria:**
- Documentation shows the recommended host-secret setup and policy shape for each supported provider
- Tests exercise the examples or share fixtures with them
- Proxy logs remain useful without leaking secret material

**Dependencies:** `m16.2`, `m16.3`, `m16.4`

**Risks:** Duplicating grammar details across docs can drift. Keep `docs/policy/schema.md` canonical and link to it from
agent-specific pages.

## Execution Order

1. Start with `m16.1` to lock the provider surface and avoid implementing a schema around guessed client behavior.
2. Implement `m16.2` early because Anthropic and Gemini need raw API-key headers.
3. Add catalog auth in `m16.3`.
4. Add the generic env shim primitive in `m16.4` only after the catalog owns the provider auth rules it pairs with.
5. Validate and document agent flows in `m16.5`.
6. Finish with the docs, examples, and regression sweep in `m16.6`.

`m16.2` can proceed in parallel with part of `m16.1` once the raw-header need is confirmed. `m16.5` should not start until
the shim behavior exists.

## Risks

- Agent CLIs may reject placeholder values before any HTTP request reaches the proxy.
- Provider clients may send credentials through headers, query strings, or provider-specific SDK internals that differ by
  version.
- A fake env var can be safe for replaceable header auth and unsafe for query-string, body, signature, or local-store
  auth. The plan should prove each catalog-owned use case instead of assuming env-token clients are equivalent.
- Broad provider host allowlists could send a powerful API key to a wider URL surface than intended.
- Users may already have real keys in persisted agent volumes; docs need to distinguish migration from fresh setup.
- OAuth-based agents will still need a different credential story, so this milestone must not overclaim "all auth".

## Definition of Done

- Provider API-key injection works for OpenAI, Anthropic, and Gemini request patterns without real keys in the agent
  container.
- Codex, Claude API-key mode, Gemini API-key mode, and provider-backed Pi/OpenCode flows have documented supported paths
  where applicable.
- Unsupported OAuth/login flows are explicitly called out and deferred to later credential-helper work.
- The policy schema, examples, and tests cover raw header injection, provider catalog auth, the generic env shim
  primitive, redaction, and fail-closed behavior.
- The roadmap treats GitHub REST wrapper, CLI monitoring, and host credential service as later milestones.

## Changes

### 2026-05-23: Created After m15

Inserted this milestone before the GitHub REST wrapper because provider API-key injection is the more direct extension
of `m15` and benefits more current agent workflows.
