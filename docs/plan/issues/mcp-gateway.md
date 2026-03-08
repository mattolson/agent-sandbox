# MCP auth broker, gateway, and host-side registry

## Problem

The core MCP problem is not simple token persistence. For agent CLIs, project-scoped persistent volumes already preserve auth state across container restarts. MCP can use a similar pattern.

The harder problem is OAuth ergonomics under a restricted network model. Today, localhost callback flows are awkward because:
- ingress is blocked by default
- container port publishing requires manual Compose edits
- some clients require deterministic callback URL and port configuration
- this setup is cumbersome to repeat per project or per MCP server

There is also a scoping problem:
- each project may need a different set of MCP servers
- the same server type may require different scopes per project
- the same service may point at different tenants, workspaces, or accounts

So the design goal is not "one global MCP auth state shared everywhere."

It is:
- make OAuth and browser-based setup easy under restricted networking
- preserve per-project MCP configuration and scope boundaries
- keep credentials durable enough to survive container restarts

The durable or host-owned parts may include:
- MCP server registry
- OAuth callback handling
- OAuth state and possibly refresh tokens
- browser-based consent flows
- local MCP server lifecycle
- MCP-specific audit logs

## Goals

- Preserve project-scoped MCP auth state across container recreation
- Make OAuth callback flows work cleanly under the sandbox network model
- Allow a separate network policy for MCP and OAuth flows
- Support both remote HTTP MCP servers and local host-managed MCP servers
- Support different MCP server sets and different OAuth scopes per project
- Avoid exposing third-party credentials to the agent container when practical
- Normalize MCP connectivity across multiple agent harnesses
- Preserve a path for host-side credential storage such as macOS Keychain or Linux secret stores

## Recommended project boundary

This should be a separate architectural subsystem, but not necessarily a separate repository yet.

### Recommendation

- keep it in the same repo initially
- design it as a separate component with a hard interface
- only split it into a separate project later if it proves useful outside `agent-sandbox`

### Why not fully couple it to agent-sandbox?

Because the concerns are different.

`agent-sandbox` owns:

- runtime isolation
- network policy for agent environments
- container or VM lifecycle
- workspace and volume wiring

The MCP subsystem would own:

- OAuth callback handling
- credential storage
- MCP server registry
- local MCP server lifecycle
- optional MCP gatewaying
- client-specific config integration

If these are tightly coupled, the MCP component will inherit assumptions that should stay optional:

- Docker Compose as the only runtime model
- container-local callback handling as the only auth flow
- Codex-specific credential storage as the only client model
- one-project-one-identity assumptions

### Recommended module boundaries

#### 1. Core MCP control plane

Owns:

- auth broker
- registry
- local server supervision
- optional gateway
- credential abstraction
- audit logs

Should not assume:

- Docker
- Compose
- a particular agent client
- a particular on-disk credential format

#### 2. Agent-sandbox integration layer

Owns:

- lifecycle wiring
- network-policy wiring
- persistent state mounts
- project-scoped enablement
- client config materialization for the active sandbox

This layer is allowed to know about:

- Docker or other runtime backends
- project layout
- sandbox networking

#### 3. Client adapters

Own:

- Codex-specific config and credential locations
- Claude Code-specific config and credential locations
- future client-specific setup flows

This keeps client quirks from contaminating the core MCP control plane.

### Suggested extraction rule

Do not split into a separate repo yet.

Revisit extraction only if one of these becomes true:

- the MCP subsystem is useful without `agent-sandbox`
- another project wants to embed it independently
- release cadence diverges from the sandbox runtime work
- the codebase starts accumulating integration workarounds because boundaries were not enforced

## Non-goals

- Replacing the MCP protocol with a custom protocol
- Solving every enterprise identity problem in the first version
- Making the first design transparent to every possible MCP client implementation
- Turning local MCP process management into a general package manager

## Why this is worth exploring

This architecture could solve several separate problems at once:

- OAuth callback friction in locked-down containers
- broader network policy in the agent container than necessary
- inconsistent MCP setup across Codex, Claude Code, and other clients
- repeated callback-port plumbing in Docker Compose
- poor lifecycle management for local MCP servers

It also creates a cleaner security boundary:

- agent container can stay network-restricted
- host or helper handles callback-oriented OAuth flows
- host manager can start and supervise local MCP servers

## Comparable implementations to review

These are important references, but they fit different layers of the problem.

### Docker MCP Gateway

Why it matters:

- probably the closest public implementation to the local workflow problem being explored here
- combines gatewaying, OAuth handling, secrets management, client configuration, and server profiles
- explicitly supports connecting multiple AI clients to a single gateway configuration

What the public docs say:

- Docker describes it as a docker CLI plugin and MCP gateway behind Docker Desktop's MCP Toolkit
- the gateway runs MCP servers as isolated Docker containers
- configuration is organized into profiles
- profiles can include catalogs, OCI references, community registry references, and local files
- clients connect to a profile rather than configuring each server independently
- built-in commands exist for secrets and OAuth flows
- configuration is stored in a local database

What to inspect:

- how OAuth callbacks are actually handled
- where tokens are stored
- how profiles map to project scoping
- how it writes client config for Claude Code and other clients
- whether the gateway can front remote MCP servers cleanly or is mostly optimized for containerized local servers

Relevance assessment:

- high relevance for:
  - auth-broker shape
  - project profile model
  - client config integration
- lower relevance for:
  - host-managed non-Docker local servers
  - strict separation between auth broker and gateway

### Microsoft MCP Gateway

Why it matters:

- shows what a fuller MCP control plane looks like when the target environment is Kubernetes
- includes control-plane APIs, data-plane routing, tool registration, and session-aware routing

What the public docs say:

- Microsoft describes it as a reverse proxy and management layer for MCP servers in Kubernetes environments
- it exposes control-plane CRUD for adapters and tools
- it exposes data-plane MCP routes such as `/adapters/{name}/mcp`
- it supports session-aware routing and a tool gateway router
- deployment targets Kubernetes, with local development using Docker Desktop plus Kubernetes
- auth examples are built around Azure Entra ID bearer tokens and application roles

What to inspect:

- whether the routing layer is useful without the full Kubernetes control plane
- how much of the design is specific to AKS and Entra
- whether local and remote MCP proxying is implemented generically or mainly for Kubernetes-hosted servers
- whether its session-affinity model aligns with how agent clients actually use MCP

Relevance assessment:

- high relevance for:
  - expanded gateway architecture
  - session-aware routing
  - control-plane API design
  - hosted or Kubernetes-backed deployments
- lower relevance for:
  - the immediate local OAuth callback pain point
  - host-side credential brokering for per-project local containers

## Key protocol constraints

These constraints come from the current MCP spec and strongly shape the design.

### HTTP-based MCP authorization is OAuth-based

The MCP authorization spec defines OAuth-based authorization for HTTP transports.

Important implications:

- remote MCP servers can require OAuth authorization
- MCP clients must discover authorization metadata
- MCP clients must use the `resource` parameter for the canonical MCP server URI

### STDIO servers are different

The MCP authorization spec explicitly says STDIO transports should not follow the HTTP OAuth flow and should instead obtain credentials from the environment or other local mechanisms.

Implication:

- local host-managed STDIO servers are a natural fit for a host control plane and credential broker

### Token passthrough is forbidden

The MCP security guidance is explicit:

- MCP servers must validate that inbound tokens were issued for themselves
- if an MCP server calls an upstream API, that upstream API must get a separate token
- MCP servers must not forward the token they received from the client to downstream services

Implication:

- a transparent auth proxy is the wrong model
- a useful gateway must terminate MCP and act as an MCP client upstream

### External third-party OAuth is separate from MCP authorization

The MCP elicitation and auth docs distinguish:

- MCP client to MCP server authorization
- MCP server to third-party resource authorization

For third-party authorization:

- the MCP server is expected to store and manage those credentials itself
- URL-mode elicitation exists specifically so sensitive credentials do not pass through the MCP client

Implication:

- if the gateway fronts upstream MCP servers, it should either:
  - let those upstream servers handle their own external OAuth, or
  - itself become the stateful server responsible for third-party credentials

## Architectural conclusion

There are two distinct problems here:

1. OAuth callback handling and credential persistence
2. MCP routing, registry, and lifecycle management

They do not necessarily require the same component in v1.

### Minimum useful design

The minimum useful design is a host-side or sibling-service auth broker that:

- handles OAuth callbacks outside the agent container
- stores project-scoped MCP credentials durably
- writes or injects those credentials where the MCP client expects them
- optionally exposes a simpler deterministic callback endpoint to the client

This design does not require terminating or proxying all MCP traffic.

### Expanded design

If we also want normalized registry, routing, local server lifecycle, or cross-client abstraction, then a fuller MCP gateway becomes attractive.

That gateway would act as:

- an MCP server to the agent container
- an MCP client to upstream MCP servers
- a credential holder for upstream MCP auth
- a registry and router for local and remote MCP endpoints

That is a much stronger architectural claim than the minimum auth-broker design and should be justified separately.

## Proposed architecture

### 1. Host MCP manager

Runs on the host and owns:

- registry of configured MCP servers
- lifecycle of local MCP servers
- installation metadata for local servers if needed
- host-side credential broker integration
- browser callback handling for OAuth when host participation is needed

Likely responsibilities:

- register local STDIO servers
- register remote HTTP MCP servers
- track per-project server enablement and scope requirements
- register server metadata such as:
  - display name
  - transport type
  - auth type
  - tenant, workspace, or account identity
  - project-specific scopes
  - network policy group
  - startup command
  - per-project availability

### 2. Auth broker

Runs on the host or in a dedicated helper with more permissive network rules than the agent container.

Owns:

- browser callback handling
- OAuth metadata discovery when needed
- token exchange and refresh
- durable project-scoped credential storage
- optional writing or syncing of credentials into a persistent volume the client already uses

This is the smallest component that directly addresses the real pain point.

### 3. Persistent MCP gateway

Optional in the first version.

Runs outside the ephemeral agent container but near it, as a sidecar or sibling service.

Owns:

- stable MCP endpoint or endpoints exposed to the agent container
- upstream MCP client sessions
- auth state and token refresh
- routing between logical server IDs and upstream connections
- audit logs for MCP requests and auth flows

The gateway should be durable across agent container recreation.

### 4. Adapters

The gateway likely needs multiple adapter types.

#### Remote HTTP adapter

- connects to remote MCP servers over Streamable HTTP
- handles OAuth metadata discovery
- stores refresh tokens outside the agent container
- can use client credentials where supported

#### Local STDIO adapter

- launches or attaches to host-managed STDIO servers
- bridges STDIO into a gateway-managed MCP surface
- injects local credentials via host-managed environment or credential broker

#### Future adapters

- WebSocket or alternate transport adapter if needed later
- registry-backed adapter for enterprise MCP catalogs

### 5. Credential broker

Should live outside the agent container.

Potential backends:

- macOS Keychain
- Secret Service on Linux
- pass or gpg-backed store
- host-local encrypted file store as fallback

The auth broker or gateway should prefer referencing stored credentials over materializing secrets into the agent container.

### 6. Policy split

This architecture becomes more useful if network policy is split by component.

#### Agent container policy

- can only reach:
  - MCP gateway
  - model APIs it needs
  - Git or package hosts if required

#### Auth broker policy

- can reach:
  - OAuth and IdP domains
  - discovery endpoints
  - token endpoints
  - remote MCP authorization metadata endpoints

#### MCP gateway policy

- can reach:
  - remote MCP servers
  - only the OAuth or IdP endpoints still needed after authentication, if any

#### Host MCP manager policy

- should mostly manage local processes
- should not need broad outbound access unless it participates directly in OAuth callbacks or installations

## Project scoping model

This needs to be explicit early, because MCP credentials are not necessarily global.

Suggested model:

- user-global registry of known MCP servers
- project-level enablement of a subset of those servers
- project-level auth material where scopes or tenant selection differ by project
- optional user-global credentials only when the upstream scopes are intentionally shared

This avoids one of the main design mistakes:

- assuming one login per service is sufficient for every repo or workspace

## Endpoint model options

There are two obvious shapes for a gateway if a gateway exists at all.

### Option A: one gateway endpoint per upstream server

Pros:

- clearer server identity
- easier mapping of logical server to upstream policy
- simpler authorization boundaries

Cons:

- more client configuration entries

### Option B: one multiplexed gateway server exposing many tools

Pros:

- simpler client configuration
- gateway can unify discovery, routing, and policy

Cons:

- more complex tool namespacing
- harder provenance and server identity model
- may blur trust boundaries between servers

Initial bias:

- start with an auth broker first
- if a gateway is needed, start with one logical endpoint per upstream server
- only add multiplexing if client UX demands it

## Security model

### Benefits

- agent containers can stay ingress-closed
- OAuth-capable network access can be restricted to the auth broker or gateway
- local MCP servers can keep secrets out of the agent container
- MCP activity can be audited in one place

### Risks

- the gateway becomes a high-value target
- gateway compromise is worse than a single agent compromise
- a multiplexing gateway may blur tool provenance
- local server bridging could expose host capabilities if the host manager is sloppy

### Security requirements

- gateway credentials stored outside the agent container
- project-scoped credentials separated where scopes differ
- strict separation of agent-facing and upstream-facing identities
- no token passthrough
- per-server audit logs
- ability to revoke or disconnect one upstream server without affecting others
- local-only bind or isolated Docker network exposure for the gateway

## Open questions

- Can the first version solve the problem with only an auth broker and no full MCP gateway?
- Should the gateway expose MCP over Streamable HTTP only, or also support STDIO locally for clients that require it?
- Should the host manager run directly on the host, or inside a small privileged helper service?
- What is the correct config model for users:
  - project-local registry
  - user-global registry
  - layered config
- How should per-project enablement work for a user-global authenticated server?
- How should token storage work across macOS and Linux without creating a fragile abstraction?
- How should callback URLs work for browser-based OAuth flows?
- How do we represent tool provenance so users know which upstream server is actually executing a tool?
- Should the gateway aggregate tools from many servers, or preserve one server per endpoint?
- How should local MCP servers be supervised, restarted, and health-checked?
- How much of this belongs in `agentbox` versus a dedicated host daemon?

## Methodical research plan

### Phase 1: protocol and client constraints

Research:

- which agent clients can talk to HTTP MCP servers versus only STDIO
- how each client configures multiple MCP servers
- where each client stores MCP auth state
- whether credentials can be pre-provisioned into that location safely
- whether clients tolerate a gateway that fronts multiple logical servers

Output:

- compatibility matrix by agent client

### Phase 2: auth-broker prototype

Decide:

- host-side broker or helper-container broker
- callback URL strategy
- credential storage format and project scoping
- how credentials are written back into persistent client state if needed

Output:

- working OAuth flow without per-project port-plumbing hacks

### Phase 3: gateway shape

Decide:

- one endpoint per server or multiplexed gateway
- sidecar service, sibling service, or host-local daemon
- agent-facing auth model

Output:

- gateway interface sketch

### Phase 4: credential model

Research and prototype:

- host keychain integration
- refresh-token storage
- per-user and per-project scoping
- disconnect and revoke flows

Output:

- credential and revocation design

### Phase 5: local server management

Prototype:

- host-side registry
- STDIO server supervision
- health checks
- bridging to the gateway

Output:

- local MCP manager proof of concept

### Phase 6: policy and observability

Add:

- separate network policy for gateway
- audit logging
- per-server policy groups
- allow and deny visibility

Output:

- end-to-end control-plane story

## Initial hypotheses

- This is likely a worthwhile control-plane feature even if the runtime backend stays container-based
- The first useful step is probably an auth broker, not a full MCP gateway
- Project-scoped auth state matters more than global shared login state
- Writing into existing persistent client state may be lower-friction than introducing a gateway immediately
- Local STDIO servers are probably best managed by a host component, not by the agent container
- Remote OAuth-heavy MCP servers are the strongest justification for a gateway
- If a gateway is added, the first version should probably preserve one logical endpoint per upstream server

## Source index

- [docker/mcp-gateway](https://github.com/docker/mcp-gateway)
- [microsoft/mcp-gateway](https://github.com/microsoft/mcp-gateway)
- [MCP authorization spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
- [MCP transports](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)
- [MCP security best practices](https://modelcontextprotocol.io/specification/2025-06-18/basic/security_best_practices)
- [MCP authorization tutorial](https://modelcontextprotocol.io/docs/tutorials/security/authorization)
- [MCP URL-mode elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation)
- [OAuth client credentials extension](https://modelcontextprotocol.io/extensions/auth/oauth-client-credentials)
- [Enterprise-managed authorization extension](https://modelcontextprotocol.io/extensions/auth/enterprise-managed-authorization)
