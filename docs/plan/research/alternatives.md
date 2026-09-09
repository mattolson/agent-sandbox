# Runtime sandbox alternatives

## How to use this document

This document should work as a research workbook, not just a dump of findings.

Use it in this order:

1. Read `Decisions to make` to stay anchored on what this research is supposed to decide.
2. Use `Prioritized research queue` to decide what to investigate next.
3. Use `Research worksheet` when reviewing any backend, product, or repo.
4. Use the `Landscape reference` sections for taxonomy and background.
5. Record conclusions in milestone plans or decision records once a question is settled.

This keeps the document useful even as the source list grows.

## Revision notes

- 2026-03-07: initial landscape and research workbook
- 2026-03 through 2026-05: worksheets for sandcat, Matchlock, and Leash; commercial product pass; exe.dev notes
- 2026-09-06: landscape refresh covering alternatives that emerged or changed since spring 2026
- 2026-09-06: merged alternatives-relevant findings from the companion architecture doc listed under `Related documents` below

What the 2026-09-06 refresh added:

- A vendor-native sandbox section: the Claude Code sandbox and `sandbox-runtime`, Codex's bubblewrap sandbox plus network proxy plus `execpolicy`, and Gemini CLI's gVisor mode and policy engine
- New open-source comparables: Coder Boundary, NVIDIA OpenShell, nono, brood-box, airut, iron-proxy, Infisical Agent Vault, httpjail, microsandbox, BoxLite, and others
- New substrates: Apple `container`, libkrun and krunkit, Lima 2.x, Tart with Softnet, Sysbox
- Hosted platform changes: Docker Sandboxes on Linux, Anthropic Managed Agents and Claude Code on the web, Codex cloud, Fly.io Sprites, Deno Sandbox, AWS AgentCore, Azure ACA Sandboxes, Superserve, Buildkite Cleanroom
- Policy-layer changes: Kubernetes `ClusterNetworkPolicy` with experimental `domainNames`, the MCP 2026-07-28 revision, agentgateway's egress mode, and the convergent hosted policy shape
- Backend-abstraction references: Harbor, Inspect, OpenHands, SWE-ReX
- Status changes: agent-embassy archived, Daytona closed-sourced, Ona and Koyeb acquisitions announced, Tart relicensed under OpenAI, Codex's Linux sandbox moved from Landlock to bubblewrap

Evidence constraints for the 2026-09-06 pass:

- Vendor pages outside GitHub and the Anthropic docs hosts could not be fetched from inside this sandbox. Claims taken from search-engine extracts of a vendor's own page are tagged `search extract` and should be re-read from the primary page before they drive a decision
- GitHub metadata such as stars, last push, and release dates was unreachable, so activity is stated only where an in-repo changelog or version file gives it
- Items that could not be verified at all are marked `unknown` rather than filled in from memory; Cursor, Factory Droid, Amp, JetBrains Junie, Kiro, Windsurf, OrbStack internals, and Freestyle fall into that group

Related documents:

- [secure-agent-sandbox-research-and-architecture.md](./secure-agent-sandbox-research-and-architecture.md): a companion architecture recommendation dated 2026-09-05. It argues for a per-task microVM with the proxy, credential broker, and workspace broker outside the guest, a no-NIC strict network mode over vsock, capability-scoped egress with limits, per-capability TLS inspection, and explicit workspace import and export. This document stays the evidence and alternatives workbook; the companion doc records the proposed target design. Facts from it that could be verified from primary sources were merged here on 2026-09-06 and are tagged normally. Claims that could not be re-verified from inside the sandbox are tagged `companion doc`.

## Decisions to make

This research should drive a small number of concrete decisions:

- What should be the default local backend?
- What should be the optional stronger-isolation backend?
- What should be the common policy model across backends?
- Which capabilities can degrade by backend, and which are mandatory?
- Which deployment targets are first-class:
  - local single-user
  - hosted multi-tenant
  - Kubernetes-managed

## Research workflow

For each item under review:

1. Classify the item by layer:
   - runtime substrate
   - control plane
   - proxy or policy layer
   - tooling or environment-definition layer
2. Verify the actual substrate from primary docs.
3. Mark every important claim as either:
   - `documented`
   - `inferred`
   - `unknown`
4. Fill out the `Research worksheet`.
5. Score the item against `Evaluation criteria`.
6. Promote only the high-signal findings into milestones or decision records.

## Prioritized research queue

### P0: likely to affect architecture decisions

- Current container plus proxy baseline
- Docker Sandboxes (`sbx`), now the mainstream local microVM comparable on macOS, Windows, and Linux
- Claude Code sandbox and `sandbox-runtime`, especially credential masking and nested-sandbox behavior inside this repo's container
- Codex network proxy and `execpolicy`
- Coder Boundary
- NVIDIA OpenShell
- CubeSandbox, for its eBPF plus transparent L7 egress data plane
- nono
- stacklok/brood-box
- gVisor
- Kata Containers
- Apple `container` and libkrun as macOS microVM substrates
- OpenSandbox
- Matchlock
- Leash
- `kubernetes-sigs/agent-sandbox`
- Harbor's capability-declared network policy as a policy-compiler precedent
- Hosted policy references: Vercel Sandbox matchers, Cloudflare per-instance CA, Anthropic GitHub proxy, Codex cloud method allowlist
- E2B
- Runloop
- exe.dev
- GKE Agent Sandbox
- MCP gateway and host-side registry
- Policy IR direction:
  - Kubernetes `ClusterNetworkPolicy` and `domainNames`
  - Cilium policy
  - Cedar
  - OPA

### P1: likely to affect packaging, portability, or UX

- Podman rootless and the libkrun machine provider
- Colima and Lima 2.x
- Finch
- Rancher Desktop
- Tart with Softnet
- Sysbox and Docker Desktop Enhanced Container Isolation
- Proxy and credential layers: airut, iron-proxy, Infisical Agent Vault, httpjail
- Gemini CLI policy engine and gVisor mode
- Inspect and OpenHands runner contracts
- Modal
- Daytona (closed source since June 2026)
- Blaxel
- Cloudflare Sandbox
- Deno Sandbox
- Fly.io Sprites
- Superserve and Buildkite Cleanroom
- Nix
- NixOS
- Devbox
- devcontainer

### P2: useful adjacent references and edge cases

- Ona (OpenAI acquisition announced)
- AgentSandbox.co
- Sandbox0
- AWS Bedrock AgentCore, Azure ACA Sandboxes, Northflank, Koyeb, Hopx, Kernel, Namespace
- Warden
- Traefik
- Varnish
- Unikraft
- Edera, Hyperlight, WebAssembly sandboxes
- Confidential Containers, only for a future tier where the cloud operator is untrusted
- microsandbox, BoxLite, arrakis, inoio/agents-sandbox, wirenboard/agent-vm, code-on-incus
- cupcake, ToolHive, node9-proxy, aicontainer
- container-use, rivet sandbox-agent, Sculptor
- `claudebox`
- `safeyolo`
- `agent-embassy` (archived)
- `sandcat`
- `claude-code-safety-net`
- `tsk`
- SWE-ReX, Vivaria, landrun

## Problem

The current project uses a Docker-based sandbox with a proxy sidecar and firewall rules.

That is a good baseline, but it is only one point in the design space. We need to explore other runtime backends that could provide:

- Stronger isolation
- Better local ergonomics
- Better portability across agent harnesses
- Better policy expressiveness for outbound network control

The target system is agent-agnostic. It should work with Codex, Claude Code, and other agent CLIs without depending on one vendor's built-in sandbox model.

## Goals

- Restrict filesystem access to:
  - A shared workspace directory backed by a host Git repo
  - Explicit scratch or temp space
  - Minimal agent state directories when required
- Restrict outbound network with policy-as-code
- Support policy evolution from coarse rules to finer-grained rules
- Normalize execution across multiple agent harnesses and model providers
- Capture logs for policy decisions, spawned processes, and denied actions
- Keep local development practical on macOS and Linux

## Non-goals

- Standardizing agent authentication flows in this phase
- Solving GUI app sandboxing first
- Committing to Kubernetes as the default runtime before proving the need

## Three control planes

Any serious sandbox design here needs three distinct control planes:

1. Filesystem access
2. Network access
3. Runtime control and observability

`Runtime control and observability` includes:

- Process isolation
- Privilege dropping
- System call reduction
- Deny/audit logging
- Policy reload or approval workflows

Treating these as one feature is a mistake. Different technologies are strong in different planes.

## Hard constraints

### HTTPS path and method policy is not free

If the requirement is "allow `GET /foo` to `api.example.com` but deny `POST /bar`", that is a Layer 7 control.

For arbitrary outbound HTTPS traffic, path and method are not visible to a host firewall or kernel LSM unless traffic is sent through an explicit proxy that can inspect decrypted HTTP, or unless the traffic is terminated and re-originated by trusted infrastructure.

Practical implication:

- Domain allowlists can be enforced with a proxy or sometimes SNI/host-aware controls
- Path and method controls for arbitrary HTTPS require MITM or a trusted outbound proxy model
- A pure OS-native firewall or pure eBPF/iptables design will not satisfy the full L7 requirement by itself

### Provider-native sandboxes are useful but not a control plane

Every major agent CLI now ships some local sandbox or permission model. As of September 2026:

- Codex documents `read-only`, `workspace-write`, and `danger-full-access` modes with network off by default; on Linux its default filesystem sandbox is now bubblewrap with Landlock kept as a legacy path, and it ships a local HTTP and SOCKS5 network proxy with per-host allow and deny rules, a read-only `limited` mode, and optional TLS termination
- Claude Code ships a sandboxed Bash tool built on Seatbelt on macOS and bubblewrap plus seccomp on Linux, with a host-side proxy, a domain allowlist, optional TLS termination, and credential masking; the runtime is open source as `sandbox-runtime`
- Gemini CLI defaults to a container sandbox, offers a gVisor mode, and has a tiered TOML tool-call policy engine
- Copilot CLI, OpenCode, and Pi document permission models or none at all; Hermes offers container backends rather than a sandbox

See `Landscape reference: vendor-native agent sandboxes` for details and sources.

Practical implication:

- Vendor-native sandboxes should be treated as defense-in-depth
- They should not be the primary portability layer if the goal is one normalized backend for many agents
- Nesting a vendor sandbox inside this repo's container is now a configuration decision, not a hypothetical; Claude Code documents a weaker nested mode for unprivileged containers, and both Claude Code and Codex can chain their proxies to an upstream proxy such as this repo's sidecar
- The vendors' own docs list the same gaps this repo's design targets: hostname-only allowlists without method or path rules by default, unfenced DNS, and domain fronting

### Global TLS inspection is a tradeoff, not a free upgrade

This repo's sidecar terminates TLS for every allowed host so that method and path rules and secret injection work everywhere. The companion architecture doc argues for two explicit paths instead:

- opaque pass-through per host: enforce destination, resolved IP class, port, SNI and Host alignment, DNS binding, byte and rate limits, and certificate expectations without decrypting; no credential injection or method and path guarantees
- inspected capability per service: terminate TLS in the host broker only for a narrowly scoped service, apply L7 policy and injection, then open a separately verified upstream connection

The reasons given are real: inspection expands the trusted parser surface and breaks certificate pinning, compressed bodies, streaming protocols, HTTP/2, Git smart HTTP, and custom trust stores. The same tension shows up in the vendor sandboxes, which default to hostname-only allowlisting and make TLS termination opt-in, and in the Codex proxy, which forces MITM only for its read-only mode.

Practical implication:

- Method and path policy still requires inspection; the open question is scope, not whether
- The policy model should be able to express per-host inspection on or off, with the documented loss of L7 guarantees when off
- Required defenses when inspecting, from the companion doc: verify SNI and Host alignment, re-resolve and re-authorize every redirect, pin connections to an authorized DNS answer and reject private and metadata ranges, normalize paths once, strip hop-by-hop headers, reject ambiguous requests, and never disable upstream certificate validation

### Kubernetes is an orchestration choice, not isolation by itself

Kubernetes adds scheduling, policy distribution, and multi-tenant operations. It does not by itself solve the isolation question. The actual isolation still comes from the runtime, kernel, proxy, and VM boundary underneath.

Practical implication:

- Do not evaluate "Kubernetes" as a sandbox
- Evaluate the runtime and policy stack that would run under Kubernetes

## Policy format landscape

There is no single cross-industry standard document format for ingress and egress policy that spans:

- host firewalls
- containers
- Kubernetes
- proxies
- VMs
- developer sandboxes

What exists instead is a set of partial standards and strong de facto formats.

### Closest de facto standard in cloud-native systems

Kubernetes `NetworkPolicy` is the closest thing to a broadly-recognized standard policy format for network ingress and egress.

Strengths:

- Widely recognized
- Native Kubernetes API
- Good mental model for pod or workload level L3 and L4 controls

Limitations:

- Only applies in Kubernetes
- Requires support from the cluster networking implementation
- Mainly targets IPs, ports, selectors, and directions
- Does not solve domain, URL path, or HTTP method policy

Update, September 2026:

- `documented`: `kubernetes-sigs/network-policy-api` replaced `AdminNetworkPolicy` and `BaselineAdminNetworkPolicy` with `ClusterNetworkPolicy` v1alpha2; the older APIs are frozen at v0.1.7 and the beta will be based on `ClusterNetworkPolicy`
- `documented`: NPEP-133 adds `domainNames` to cluster network policy egress peers, Accept action only, at most 25 per peer, marked experimental with extended support; the design excludes DNS filtering and L7 matching and assumes pods use cluster DNS with TTL-bound IPs
- `documented`: Cilium `toFQDNs` still requires the L7 proxy and a DNS rule so the agent's DNS proxy sees answers; Calico documents domain-based policy in its enterprise docs, with open-source availability `inferred` as absent

Practical conclusion:

- Use Kubernetes `NetworkPolicy` and `ClusterNetworkPolicy` as important compatibility targets, not as the project's top-level policy model
- As of 2026 there is still no GA Kubernetes standard for name-based egress; a policy IR could lower host allowlists to `domainNames` but has no Kubernetes target for method or path rules other than Cilium L7

### Common extension model

Cilium extends the basic Kubernetes model with richer policy CRDs and L7-aware controls.

This is useful because it shows the likely shape of the real world:

- one baseline standard
- richer provider-specific extensions for actual deployments

Practical conclusion:

- Expect backend-specific extensions even if the project defines a common policy IR

### Formal network-management standards

IETF YANG ACL models are real standards for describing access-control lists in network devices and network-management systems.

Strengths:

- Standards-track specification
- Useful reference for thinking about normalized rule structure

Limitations:

- Not the format modern sandbox products actually use
- Not designed as a practical authoring format for developer sandbox HTTP egress policy

Practical conclusion:

- Treat YANG ACL as a standards reference, not as the likely authoring format for this project

### Policy languages, not network-policy standards

OPA and Cedar are policy languages or policy engines, not standard network ingress or egress document formats.

They may still matter a lot.

Potential uses:

- defining a higher-level policy IR
- evaluating policy decisions consistently across backends
- separating policy intent from runtime-specific compilation

Limitations:

- they do not by themselves provide transport enforcement
- they do not remove the need for proxies, firewalls, or runtime hooks
- they are not drop-in replacements for Kubernetes `NetworkPolicy` or proxy configuration

Practical conclusion:

- OPA and Cedar are worth separate research as policy-engine candidates, not as existing network-policy standards

### Agent-native policy surfaces

Three vendor dialects now exist for tool-call and command policy, and two of them also carry network policy:

- Codex `execpolicy`: `documented`, Starlark `prefix_rule` entries with `allow`, `prompt`, or `forbidden` decisions matched against command token sequences, strictest decision wins, files under `$CODEX_HOME/rules/`, approvals appended automatically; a newer `network_rule` grants a specific hostname or IP per protocol; an admin overlay merges organization rules
- Codex network proxy: `documented`, per-host allow and deny with `*.` for subdomains only and `**.` for apex plus subdomains, a global `*` rejected, a `limited` mode that permits only GET, HEAD, and OPTIONS and forces TLS termination, MITM hooks keyed on host, methods, and path prefixes with named actions such as stripping authorization headers, private-IP resolution blocked by default, and OpenTelemetry audit events
- Claude Code permissions and hooks: `documented`, `Tool(pattern)` rules in `allow`, `ask`, and `deny` lists with Bash prefix wildcards and `WebFetch(domain:host)`, deny then ask then allow with first match, shell-operator awareness, `PreToolUse` hooks that return allow, deny, or ask decisions and can rewrite input, and managed settings delivered through system paths, macOS plists, and Windows registry keys with `allowManagedPermissionRulesOnly`; the docs themselves say argument-constraining Bash rules are fragile and recommend denying `curl` and `wget` in favor of domain rules or hooks
- Claude Code sandbox network and credentials: `documented`, `allowedDomains` and `deniedDomains`, `strictAllowlist`, `allowManagedDomainsOnly`, `tlsTerminate`, and `credentials` entries in `mask` mode with `injectHosts`, header and body substitution, and SigV4 re-signing
- Gemini CLI policy engine: `documented`, TOML rules with tool names, MCP names, `argsPattern`, `commandPrefix`, `commandRegex`, modes, and priorities across default, workspace, user, and admin tiers where admin outranks all; no network surface
- Third-party engines: cupcake compiles Rego to Wasm for Claude Code, Cursor, Factory, and OpenCode hooks; Invariant Guardrails evaluates Python-like rules over tool calls and data flows in an MCP and LLM gateway; Leash's Cedar model covers file open, process exec by path only, network connect by host and port, HTTP rewrite, and MCP call

Practical conclusion:

- A policy IR for exec rules could target all three vendor dialects, but only Codex and Claude Code accept network rules, and neither accepts path rules for general egress
- Codex's `limited` mode and path-prefix hooks are the closest vendor analog to this repo's method and path rules

### Hosted sandbox policy shape

Across Vercel, Cloudflare, E2B, Modal, Deno, Docker Sandboxes, OpenSandbox, and Anthropic's hosted runtimes, network policy has converged on one shape:

- a default of allow or deny
- an allowlist of hostnames, wildcard domains, IP literals, and CIDRs, sometimes with ports
- proxy-side credential injection with placeholder values inside the sandbox
- an increasing minority with HTTP method, path, query, or header matchers: Vercel matchers, Codex cloud method allowlists, Codex CLI `limited` mode, Coder Boundary, nono endpoint policies, and OpenShell read-only endpoint presets
- live policy updates without restart in most products, with Koyeb as the exception that redeploys

Harbor is the only public normalization of this shape into a typed policy plus a per-backend capability declaration, with fail-closed validation when a backend cannot enforce an entry type. That pattern is the strongest precedent for the compile step proposed below.

### MCP protocol changes relevant to proxies

- `documented`: the 2026-07-28 MCP revision removes protocol-level sessions and the `initialize` handshake, carries version and capabilities in `_meta`, adds `server/discover`, replaces the GET stream with `subscriptions/listen`, moves tasks to an extension, and tightens authorization with issuer validation and issuer-bound credentials
- `documented`: `Mcp-Method` and `Mcp-Name` request headers now give an L7 proxy routing keys without parsing JSON-RPC bodies
- Practical conclusion: MCP policy at the proxy is becoming feasible without deep body inspection; this belongs in the MCP gateway track

### Recommendation for this project

Define one internal policy model with graceful degradation.

Compile that model to backend-specific controls such as:

- Kubernetes `NetworkPolicy` and `ClusterNetworkPolicy`
- Cilium policy
- proxy rules
- host firewall rules
- runtime allowlists
- vendor sandbox settings where an agent's own proxy is chained to the sidecar

Likely policy layers:

- `transport`
  - CIDR
  - port
  - protocol
- `name`
  - hostname
  - wildcard domain
  - service alias
- `dns`
  - allow the system resolver, sinkhole to the proxy, or resolve only proxy-side
- `http`
  - method
  - path
  - header transforms
  - secret injection
- `credentials`
  - placeholder mapping
  - inject hosts and surfaces such as header, query, path, and body
  - re-signing for signature schemes such as SigV4
- `limits`
  - redirect handling and re-authorization
  - request and response byte caps
  - connection, request, and token rate
  - capability lifetime and idle expiration
  - whether request or response bodies may pass
- `execution`
  - allow or deny capabilities by backend

Borrow Harbor's contract shape: each backend declares which layers and entry types it can enforce, and a run fails closed when the policy asks for something the backend cannot enforce.

### Follow-up research

- Research Cedar in detail:
  - authoring model
  - embedding model
  - partial evaluation story
  - suitability as a portable policy IR
- Research OPA in detail:
  - Rego authoring ergonomics
  - evaluation latency and caching
  - embedding model
  - suitability as a portable policy IR
- Compare Cedar versus OPA specifically for:
  - human authorability
  - policy review workflows
  - backend compilation
  - explainability of allow and deny decisions
  - fit for both local CLI and hosted control-plane use
- Compare Harbor's environment capabilities and Inspect's sandbox environment interface against the proposed backend interface
- Decide whether Codex `execpolicy`, Claude Code permission rules, and Gemini policy TOML are compile targets or out of scope
- Track `ClusterNetworkPolicy` `domainNames` toward beta
- Cedar 4.12 and OPA 1.20 release notes carry no network-specific changes; revisit only if the IR decision lands on one of them

## Evaluation criteria

Every candidate backend should be scored against the same criteria:

- Filesystem isolation strength
- Network isolation strength
- Network policy expressiveness
- DNS exfiltration resistance
- Credential exposure model: does the agent ever hold a real secret
- Live policy update without restarting the sandbox
- Runtime syscall and privilege control
- Auditability and logging quality
- Bypass resistance
- VMM and helper confinement on the host, for VM-backed backends
- Cross-agent compatibility
- macOS local support
- Linux local support
- Apple Silicon support
- Intel Mac support, since several new microVM tools drop it
- Startup latency
- Interactive CLI ergonomics
- CI friendliness
- Operational complexity
- Implementation complexity
- License and source availability

## Landscape reference: stack taxonomy

One source of confusion in this space is that many popular tools span different layers.

Useful layers:

1. Host hypervisor or VM substrate
2. Guest runtime manager
3. Container engine or VM runtime
4. Orchestrator
5. Application proxy, routing, and caching
6. Policy enforcement and observability
7. Reproducibility and image-definition layer

Examples:

- Lima, WSL2, QEMU, Apple Virtualization.Framework: host hypervisor or VM substrate
- Colima, Finch, Rancher Desktop, Podman Machine: guest runtime managers
- Docker Engine, Moby, containerd, Podman, Incus, Firecracker, Kata: container or VM runtimes
- Kubernetes, K3s, KubeVirt, Rancher: orchestration and fleet management
- Traefik, Envoy, mitmproxy, HAProxy, Nginx, Varnish: application proxy, routing, and caching
- Cilium, iptables, Landlock, seccomp, AppArmor, SELinux, Tetragon: enforcement and observability
- Nix, NixOS modules, flake outputs: reproducibility and image-definition layer
- Devbox: developer environment definition on top of Nix
- Dev Container spec and tooling: development-environment definition and workflow layer on top of containers or remote runtimes

The same product can touch more than one layer, but this separation prevents category errors.

## Landscape reference: runtime substrate families

### 1. OS-native sandbox wrapper

Examples:

- macOS App Sandbox or seatbelt-style policy enforcement
- Linux `bubblewrap` plus `seccomp`
- Linux `Landlock`
- Linux AppArmor or SELinux as additional policy layers
- Agent-specific wrappers: Claude Code sandbox and `sandbox-runtime`, Codex's Linux sandbox, nono, Coder Boundary

Strengths:

- Lowest runtime overhead
- Fast startup
- Good fit for local CLI workflows
- No full guest OS required

Weaknesses:

- Cross-platform policy mismatch is severe
- macOS public sandbox APIs are app-entitlement oriented, not a clean general-purpose CLI sandbox product surface
- Linux feature coverage depends heavily on kernel version and distro configuration
- Network policy is weak without a proxy layer
- Logs and audit behavior are fragmented across platforms

Notes:

- Apple App Sandbox is kernel-enforced and can restrict file and network entitlements, but its public model is built around sandboxed apps and entitlements, not arbitrary third-party CLI harnesses
- Landlock now supports unprivileged filesystem rules, TCP bind/connect port rules, and newer IPC scoping, but it still does not solve domain or URL policy
- `documented`: Landlock at kernel HEAD is at ABI 11 and adds UDP bind and connect-send rules, pathname UNIX socket rules, signal and abstract-socket scoping, audit logging flags, thread-synchronized enforcement, and a no-new-privileges flag; there is still no hostname concept
- `seccomp` is valuable for syscall reduction, but it is not a filesystem or URL policy mechanism
- Claude Code, Codex, and nono have converged on bubblewrap or Landlock on Linux and Seatbelt on macOS with a host-side proxy for network policy; `sandbox-runtime` and nono are the reference implementations for an `os-native` backend
- Coder Boundary shows the Linux-only variant: a network namespace plus an iptables redirect into a MITM proxy plus a dummy DNS server, with a Landlock fallback that relies on advisory proxy environment variables

### 2. Hardened containers

Examples:

- Docker or Podman
- Rootless container engines
- Existing proxy sidecar plus firewall model
- Sysbox and Docker Desktop Enhanced Container Isolation

Strengths:

- Mature operational model
- Good bind-mount semantics for a shared workspace
- Good compatibility with current agent CLIs
- Familiar packaging and image distribution

Weaknesses:

- Shared-kernel boundary is weaker than VM-backed options
- Rootless and host portability details vary
- Fine-grained network policy still wants a proxy

Notes:

- This is the current baseline
- It should remain the control case in every benchmark and security comparison
- Sysbox and Enhanced Container Isolation harden this family with user namespaces, procfs virtualization, and syscall trapping without leaving the shared kernel
- airut, aicontainer, node9-proxy, and NVIDIA OpenShell are 2026 examples of this family with mitmproxy, iptables, or L7-proxy egress control
- The companion architecture doc's main critique of this baseline: on macOS the agent container and the trusted proxy sidecar share Colima's guest kernel, so a container escape reaches the enforcement point and the secret mount; the outer VM still protects the physical host but not the controls

### 3. Sandboxed containers with stronger runtime isolation

Examples:

- gVisor
- Kata Containers

Strengths:

- Better isolation than plain containers
- Still speaks OCI and works with existing container tooling
- Much better fit than bespoke runtimes if we want to stay container-compatible

Weaknesses:

- More compatibility risk than plain containers
- More runtime complexity
- Still needs a separate answer for L7 outbound policy

Notes:

- gVisor is strong for syscall mediation and host-kernel attack-surface reduction
- Kata is attractive when the requirement is "container UX with VM isolation"
- `documented`: Kata 4.x makes the built-in Dragonball VMM the default and recommended configuration, with QEMU, Cloud Hypervisor, and Firecracker as external options and QEMU as the path for GPUs and confidential computing; the earlier "Cloud Hypervisor default" framing in this doc applies to the 3.x line
- `documented`: Gemini CLI exposes gVisor directly through `docker run --runtime=runsc`, and Inspect's Kubernetes sandbox defaults to the gVisor runtime class
- `documented`: gVisor release packaging changed in July 2026 to a multi-file layout; GKE Pod Snapshots use gVisor checkpoint and restore in production, including GPU state

### 4. Direct microVM backend

Examples:

- Firecracker
- Cloud Hypervisor
- Apple Virtualization.framework-based runner on macOS
- libkrun on Linux and Apple Silicon
- Apple `container`

Strengths:

- Strong isolation boundary
- Small guest footprint compared with full VMs
- Good fit for ephemeral per-task sandboxes

Weaknesses:

- Highest implementation cost if built directly
- Guest image creation and update pipeline becomes part of the product
- File sharing, networking, and log streaming need custom plumbing
- Cross-platform parity is hard

Notes:

- Firecracker is excellent for secure, high-density microVMs on Linux
- A direct Firecracker path is compelling for Linux-first infrastructure, but it is not a simple local macOS story
- `documented`: Docker Sandboxes is now the mainstream product in this family on macOS, Windows, and Linux with KVM, with a private Docker daemon per sandbox
- `documented`: Apple `container` gives one Virtualization.framework VM per container on Apple Silicon with OCI images, but no compose layer and no egress primitive
- `documented`: libkrun is the substrate under microsandbox, BoxLite, brood-box, and the default Podman machine provider on macOS; its docs say the VMM and guest share a security context, so the VMM process itself must be confined
- `documented`: Firecracker 1.17 and Cloud Hypervisor v53 continue as Linux-only substrates; Cloud Hypervisor is also the Linux backend of Apple's `containerization` package
- `documented`: Firecracker's jailer confines the VMM with a chroot through `pivot_root`, cgroups, uid and gid drop, mount, PID, and network namespaces, and rlimits; the companion doc adds per-thread seccomp filters in the default build (`companion doc`, seccomp doc not read here)
- `documented`: CubeSandbox runs each sandbox in a KVM microVM behind an eBPF virtual switch and a transparent L7 egress proxy; see the open-source comparables

### 5. Full VM backend

Examples:

- Lima or Colima style VM-per-project
- QEMU or libvirt
- Hypervisor-backed local VM running Docker inside
- Tart on Apple Silicon

Strengths:

- Strongest isolation
- Easiest mental model for "untrusted code runs in another machine"
- Good fallback for high-risk workloads

Weaknesses:

- Slowest startup
- Heaviest resource use
- More friction for interactive local use
- More moving parts for workspace sync and policy management

Notes:

- This may be the right "maximum isolation" backend even if it is not the default
- `documented`: Tart with Softnet is the one full-VM manager found with a VM-level egress filter on macOS, but it is FSL-licensed and now owned by OpenAI
- `documented`: Lima 2.x adds a `krunkit` driver and named networks but still has no egress policy option

### 6. Kubernetes-native virtualization and policy stacks

Examples:

- KubeVirt on Minikube
- Kata under Kubernetes
- Cilium for L3-L7 policy and visibility

Strengths:

- Strong fit if the product eventually needs multi-tenant cluster orchestration
- Central policy distribution
- Strong observability potential
- Good place to test Cilium HTTP-aware policy and Hubble logging

Weaknesses:

- Large operational surface area
- Local developer UX is much heavier
- KubeVirt on Minikube may require nested virtualization or emulation
- It is easy to spend time on cluster plumbing before validating the runtime choice

Notes:

- KubeVirt documents a Minikube quickstart, but also documents nested virtualization and emulation concerns
- This should be a later-stage exploration unless cluster deployment is a near-term product requirement
- `documented`: `ClusterNetworkPolicy` v1alpha2 with experimental `domainNames` is the emerging Kubernetes shape for name-based egress; it standardizes DNS-snooping-derived IP allowlists and excludes L7 matching
- `documented`: Inspect's Kubernetes sandbox is a working reference stack: gVisor runtime class, Cilium FQDN policy limited to ports 80 and 443 with SNI enforcement, and a per-pod CoreDNS sidecar
- Confidential Containers layers attestation and key release on Kata for the case where the cloud operator is untrusted; it does not address egress and is a separate future tier at most

## Landscape reference: supporting layers and tools

### Colima

Best fit:

- Full VM backend on macOS
- Guest runtime manager for Docker, containerd, or Incus
- Optional single-node local Kubernetes

What it is:

- Colima describes itself as "Containers on Lima"
- It wraps Lima and exposes Docker, containerd, optional Kubernetes, and even Incus

What it is not:

- Not a policy engine
- Not a new isolation primitive beyond "Linux VM on the host, then runtime inside"

Practical use here:

- Good replacement substrate for the current Docker-based design on macOS
- Useful when the goal is "keep container UX, but move the trust boundary to a Linux VM"

### Finch

Best fit:

- Full VM backend on macOS and Windows
- Guest runtime manager around containerd inside a VM

What it is:

- Finch documents a stack of Lima, nerdctl, BuildKit, containerd, and QEMU on macOS
- It is primarily a local container platform, not an isolation framework by itself

What it is not:

- Not a policy engine
- Not a distinct sandbox family from Colima

Practical use here:

- Another way to run a container backend inside a Linux VM
- Strong candidate if the project wants a containerd or nerdctl-first user experience

### Rancher Desktop

Best fit:

- Full VM backend for local development
- Optional Kubernetes track via bundled K3s
- Local container platform with either containerd or Moby

What it is:

- Rancher Desktop is a desktop app that ships local container management and optional Kubernetes
- Its docs expose both `containerd` and `dockerd` modes, plus built-in K3s
- On macOS and Linux it exposes Lima customization hooks; on Windows it integrates with WSL

What it is not:

- Not the same thing as Rancher Manager
- Not a policy engine

Practical use here:

- Relevant if the product wants a polished desktop UX with an optional Kubernetes local path
- More of a developer platform choice than a core security architecture choice

### Rancher

Best fit:

- Kubernetes management plane
- Multi-cluster orchestration and policy distribution

What it is:

- Rancher positions itself as a complete container management platform for Kubernetes

What it is not:

- Not a local agent sandbox runtime
- Not a replacement for a container engine, VM runtime, or outbound policy proxy

Practical use here:

- Only becomes relevant if this project grows into a cluster-managed or fleet-managed deployment model

### Podman

Best fit:

- On Linux: hardened containers bucket
- On macOS and Windows: full VM backend through Podman Machine

What it is:

- Podman is a daemonless, Linux-native OCI container engine with strong rootless support
- On Linux, rootless mode uses user namespaces and related isolation primitives
- On macOS and Windows, `podman machine` starts a Linux VM where containers run

What it is not:

- Not a complete outbound policy solution
- Not a single category across all platforms

Practical use here:

- Strong Linux candidate if rootless OCI is attractive
- On macOS it behaves much more like Colima or Finch than like native Linux Podman

### Moby

Best fit:

- Hardened containers bucket on Linux
- Container engine or platform-assembly layer
- Upstream substrate for Docker Engine and parts of Docker Desktop

What it is:

- Moby describes itself as an open framework for assembling specialized container systems
- It is the upstream open-source project behind Docker Engine
- Moby uses `containerd` as the default container runtime

What it is not:

- Not a separate sandbox family from Docker Engine for this evaluation
- Not a policy engine
- Not the same thing as Docker Desktop

Practical use here:

- On Linux, treat Moby-based Docker Engine as part of the current hardened container baseline
- On macOS and Windows, if Moby is consumed through Docker Desktop, the effective runtime shape becomes "Linux VM plus Moby or Docker Engine inside"
- So Moby matters mainly as the implementation substrate, not as a new top-level backend choice

### Docker Sandboxes

Best fit:

- Direct microVM backend
- Host-managed agent sandbox product; the closest commercial analog to this repo

What it is:

- `documented`: `sbx` is a standalone CLI that no longer requires Docker Desktop or Docker Engine; the experimental `docker sandbox` plugin was removed in Docker Desktop 4.80 in favor of `docker sbx`; version 0.39.0 shipped on 2026-08-19 and the product is free for commercial use with paid organization governance
- `documented`: each sandbox is a microVM with its own kernel and private Docker daemon; the agent runs as a non-root user with sudo, and Docker describes the hypervisor boundary as the isolation control
- `documented`: the workspace is a virtiofs passthrough at the same absolute path, with an optional `--clone` mode that mounts the repo read-only and works on an in-VM clone; hard-link escape from direct mounts is acknowledged
- `documented`: supported agents include Claude Code, Codex, Copilot, Cursor, Droid, Gemini, Kiro, OpenCode, and a plain shell

Network model:

- `documented`: all outbound TCP goes to a host-side proxy: a TLS-terminating forward proxy for HTTP and HTTPS and a transparent proxy for other TCP; UDP and ICMP are always blocked; an internal DNS resolver enforces policy
- `documented`: rules are `connect:tcp` on hostnames with `*` and `**` wildcards, CIDRs, and ports, with Open, Balanced, and Locked Down presets, `--deny-network` per sandbox, and organization governance that overrides local allows
- `documented`: no HTTP method or path rules exist in the rule syntax; only HTTP and HTTPS can chain to an upstream proxy
- `documented`: Docker's own docs note that the proxy cannot distinguish reading docs from posting a gist on an allowed domain, and that domain fronting is a limit

Secrets and MCP:

- `documented`: credentials are injected as headers by the host proxy with sentinel values inside the VM; OAuth flows run host-side and secrets live in the OS keychain
- `documented`: filesystem policies for host paths and Cedar-based MCP policies enforced at a host-side MCP gateway were added

What it is not:

- Not open source; the daemon ships from a release-only repository
- Not a method or path aware L7 policy engine
- Not a layered compose and policy model that users own

Platform support:

- `documented`: macOS 14+ on Apple Silicon only, Windows 11 with the Windows Hypervisor Platform, and Linux with KVM on Ubuntu 24.04+; GPU passthrough is Linux-only; the macOS hypervisor is not named

Practical use here:

- This is the product to benchmark against for the stronger-isolation backend and for local UX
- Differentiators this repo keeps: TLS-inspecting method and path rules, user-owned compose and policy layers, Intel Mac support through Colima, and open source
- Ideas worth adopting: a per-sandbox private daemon, a policy-decision log with a per-request proxy mode column, and the honest "allowed domain is not safe content" framing in docs

### Apple `container` and Containerization

Best fit:

- Direct microVM backend on Apple Silicon
- Combined hypervisor substrate, guest runtime manager, and OCI runtime in one tool

What it is:

- `documented`: one lightweight Linux VM per container, driven by a launchd API server with XPC helpers and a per-container runtime process; the guest init is `vminitd` over vsock; it consumes and builds OCI images
- `documented`: the default kernel is a Kata `vmlinux` from the `kata-static` tarball and can be overridden per container; nested virtualization needs M3 or later and macOS 15 or later
- `documented`: the `containerization` Swift package now includes a Cloud Hypervisor plus KVM backend for Linux hosts with the same `vminitd` contract, but the CLI itself is macOS-only
- `documented`: pre-1.0, with breaking changes allowed between minor versions; memory freed in the guest is not returned to the host
- `companion doc`: the `containerization` repo carries public security advisories covering image extraction, copy operations, identifiers, and registry handling, which places image handling inside the trusted base; the advisories were not readable from inside this sandbox

Networking and mounts:

- `documented`: vmnet-backed networks with a per-container IP, isolated custom networks and custom subnets on macOS 26, embedded DNS, and port publishing; macOS 15 runs with no `container network` commands
- `documented`: bind mounts of host directories plus named sparse ext4 volumes and tmpfs
- `unknown`: whether a network can be created without NAT egress; forcing traffic through a proxy would need in-guest firewall rules plus a proxy container on the same network (`inferred`)

What it is not:

- Not a Docker Engine API or compose implementation
- Not available on Intel Macs
- Not a policy engine

Practical use here:

- The most direct Apple-supported microVM substrate for a `microvm` backend on the primary target platform
- Adopting it means reimplementing the compose layer and egress enforcement, which is a large cost relative to Colima plus Docker
- Harbor already lists an `apple-container` environment, which is a cheap way to see the integration surface

### libkrun, krunkit, and Podman machine

Best fit:

- Direct microVM substrate as a library on Linux and Apple Silicon
- The VMM under microsandbox, BoxLite, brood-box, and Podman machine on macOS

What it is:

- `documented`: libkrun is an embeddable VMM using KVM on Linux and Hypervisor.framework on ARM64 macOS with a minimal device set; krunkit is the macOS CLI around it; crun's `krun` handler runs an OCI container inside a libkrun microVM with annotations for CPUs, RAM, GPU, passt networking, and nested virtualization
- `documented`: Podman's machine documentation at HEAD marks libkrun as the default macOS provider with `applehv` as the alternative; when the default switched is `unknown`
- `documented`: Lima 2.x ships an experimental `krunkit` driver
- `documented`: the 1.x line is at 1.19.4 and the 2.0 line on `main` breaks API and ABI compatibility

Security model:

- `documented`: the libkrun docs say the guest and VMM share a security context, virtio-fs does not stop a guest from reaching other directories on the same filesystem, and under TSI networking the VMM and guest run in the same network context
- Practical consequence: the VMM process must itself be confined with namespaces, user isolation, or seccomp; BoxLite documents exactly that wrapping

Networking:

- `documented`: either TSI socket impersonation over vsock with TCP, UDP, and UNIX sockets only, or virtio-net to passt, gvproxy, or vmnet-helper; egress control is applied by constraining the VMM process or the userspace network proxy (`inferred`)

Practical use here:

- The most realistic open-source substrate for a `microvm` backend that runs on both Linux and Apple Silicon
- Using it via Podman machine or crun `krun` keeps OCI semantics; using it directly means building the runtime layer, which is what microsandbox and BoxLite already did

### Lima 2.x

- `documented`: version 2.2.0 in Homebrew; drivers `vz` (macOS default since 1.0), `qemu`, `wsl2`, and experimental `krunkit`; virtiofs mounts by default under `vz`; user-mode networking by default with `vzNAT`, `socket_vmnet`, and new named networks through `limactl network`
- `documented` by absence: no egress policy or firewall option at the VM level
- Practical use here: Colima's substrate; the `krunkit` driver is a possible path to per-VM libkrun without leaving the Lima toolchain

### OrbStack

- `documented` from the issues-only README: a native macOS app that runs Docker containers, Linux machines, and Kubernetes
- `unknown`: architecture, isolation features, network policy, and licensing terms; the docs site was unreachable in this pass
- Practical use here: users may run this repo's compose stack on OrbStack's daemon, but nothing OrbStack-specific can be relied on; Harbor's docs mention OrbStack as a workaround when Docker Desktop's kernel lacks nftables features

### Tart and Lume

Tart:

- `documented`: a Virtualization.framework runner for macOS and Linux VMs on Apple Silicon with OCI-registry distribution of VM images; version 2.36.0 in OpenAI's Homebrew tap
- `documented`: the license is FSL-1.1-ALv2 with copyright assigned to OpenAI for 2022 through 2026, and the README installs from OpenAI's tap; the FSL forbids offering a competing commercial product
- `documented`: `--net-softnet` enables Softnet, a userspace packet filter that pins a VM to its own MAC and IP, blocks host access, and supports stateful inbound and outbound rules; this is the only VM-level egress primitive found among macOS VM managers
- `documented`: virtiofs directory sharing with a read-only option; nested virtualization on M3 or later for Linux guests; arm64 guests only

Lume:

- `documented`: an MIT-licensed Virtualization.framework CLI from the Cua project aimed at computer-use agents, with macOS install presets, VNC, and shared directories; telemetry is on by default
- `unknown`: networking and egress controls

Practical use here:

- Tart is the strongest full-VM backend candidate on Apple Silicon because of Softnet, with the license as the blocker to weigh
- Lume is low relevance for headless coding sandboxes

### Sysbox and Enhanced Container Isolation

- `documented`: Sysbox 0.7.1 is an Apache-2.0 runc fork using user namespaces, partial procfs and sysfs virtualization, and syscall trapping so containers can run Docker, Kubernetes, and systemd without `--privileged`; Linux hosts only; the project describes its isolation as stronger than plain containers but weaker than VMs and notes kernel CVEs have periodically weakened it
- `documented`: Docker Desktop Enhanced Container Isolation is implemented with Sysbox, applies to every container silently, maps root to an unprivileged host range, contains `--privileged`, and blocks host PID, network, and user namespaces; it requires a Business subscription
- `inferred`: Daytona's default runtime uses Sysbox according to its security materials, which is the main production example
- Practical use here: the natural hardening step for the current container baseline on Linux hosts, especially for agents that need nested Docker; not applicable inside Colima without further verification

### Edera, Hyperlight, and WebAssembly sandboxes

- Edera: `documented` from its open-source components, each Kubernetes pod runs in a paravirtualized Xen guest with its own kernel and an embedded OCI runtime, without nested virtualization; server and Kubernetes only, with aarch64 support incomplete in the published table; low relevance for a laptop tool
- Hyperlight: `documented`, a CNCF sandbox project at 0.17.0 that runs `no_std` guest binaries or Wasm components in kernel-less micro VMs on KVM, MSHV, and WHP, with no filesystem or network access and explicitly not for Linux workloads; no macOS support; low relevance beyond MCP tool servers
- WebAssembly and WASI: capability-based sandboxes for single tools, not for a Linux toolchain with Docker and package managers; low relevance for the sandbox itself, possible supporting layer for tool servers

### Unikraft

Best fit:

- Direct microVM and unikernel backend
- Specialized VM image runtime for tightly-scoped workloads

What it is:

- Unikraft documents itself as a unikernel development kit for building minimal virtual machines with hardware-level isolation
- It can run directly as a VM using KVM with QEMU or Firecracker as VMMs, and it can also integrate with OCI tooling through the `runu` runtime
- It supports Linux and POSIX compatibility through a syscall shim and a binary-compatibility layer for Linux ELFs

What it is not:

- Not a normal Linux distribution inside a VM
- Not a drop-in replacement for a mutable shell-heavy developer workstation
- Not a complete outbound policy solution

Practical use here:

- Interesting as a high-isolation backend for narrowly-scoped helper services or single-purpose workloads
- Potentially useful for hardened sidecars such as proxy or policy components
- Worth studying for its OCI integration model and Firecracker path

Important limitations:

- Unikraft is optimized around specialized application images, not general interactive development environments
- The docs describe compatibility as Linux-like rather than full Linux equivalence
- Binary compatibility is currently documented as available on `x86_64`, with AArch64 work ongoing
- Local OCI integration through `runu` requires a Linux host with virtualization enabled
- Root filesystems are often initramfs-based and read-only by default, though external volumes and host path mounts are supported

Assessment:

- Inference from the docs: Unikraft is probably a poor default runtime for Codex or Claude Code style sessions that expect broad Linux userspace behavior, package installs, shells, and mutable workspace workflows
- It is more plausible as:
  - a specialized backend for bounded tasks
  - a hardened service appliance
  - a research track for "can a minimal VM run one specific agent workload"

### Warden

Best fit:

- Guest runtime manager and local development workflow layer
- Docker Compose based environment orchestrator on top of Docker Engine

What it is:

- `warden.dev` documents Warden as a local development tool that runs environments under `docker-compose` via Docker Engine
- It manages shared services such as Traefik, Portainer, and Dnsmasq plus per-project containers
- It supports custom per-project Compose overlays through `.warden/warden-env.yml`

What it is not:

- Not a new isolation primitive
- Not a policy engine
- Not an AI-agent sandbox framework

Important distinction:

- `warden.dev` is the Docker and Compose local development project
- `wardendocs.com` appears to describe a separate AI framework also called Warden
- They should not be grouped together in this exploration

Practical use here:

- Treat `warden.dev` as a specialized Docker Compose frontend similar in spirit to devcontainer tooling, but aimed at local web-app environments
- If you reused it at all, it would sit above the current container baseline as an orchestration UX layer
- It does not change the core sandbox answer for filesystem, network, or syscall control

### Traefik

Best fit:

- Application proxy, routing, and middleware layer
- Ingress or edge-router component in front of services

What it is:

- Traefik documents itself as an open-source application proxy and edge router
- It receives requests, discovers services, and routes traffic based on host, path, headers, and other request properties
- It also supports middleware that can transform or gate requests before forwarding

What it is not:

- Not a primary sandbox boundary
- Not a host-level filesystem or syscall control
- Not the right first choice for arbitrary outbound agent egress policy

Practical use here:

- Strong fit for inbound routing into sandboxed services
- Potential fit as part of a trusted internal control plane or API gateway
- Usually the wrong core tool for "agent may only call these outbound domains and methods" unless the architecture is explicitly built around a forward-proxy or gateway pattern

### Varnish

Best fit:

- Application proxy and HTTP caching layer
- Reverse caching proxy or HTTP accelerator in front of web or API services

What it is:

- Varnish documents itself as a reverse caching proxy that speaks HTTP and sits in front of origin servers
- Its core strength is serving cacheable content from memory and shielding origins from repeated requests

What it is not:

- Not a primary sandbox boundary
- Not a general-purpose outbound policy engine
- Not a filesystem or syscall isolation tool

Practical use here:

- Potentially useful if the sandbox architecture eventually needs response caching for approved internal APIs or package mirrors
- Not a natural fit for agent egress control
- Much less relevant than mitmproxy, Envoy, or Cilium for the policy questions in this project

### Devbox

Best fit:

- Reproducibility and developer-environment definition layer
- Nix-based package and shell management for local development

What it is:

- Devbox presents itself as a way to create isolated, reproducible development environments using the Nix package manager
- Its docs explicitly say Docker is not required
- It can also generate `Dockerfile` and `devcontainer.json` outputs when you do want a containerized environment

What it is not:

- Not a primary filesystem sandbox for arbitrary agent execution
- Not a network policy engine
- Not a replacement for a VM, container runtime, or proxy

Practical use here:

- Strong candidate for defining the toolchain used inside any backend
- Useful for normalizing package installation across host shells, containers, and VM guests
- Best treated as complementary to the sandbox, not as the sandbox itself

### Devcontainer

Best fit:

- Development-environment specification and workflow layer
- Container-oriented packaging around an underlying runtime

What it is:

- The Development Container Specification is an open spec for enriching containers with development-specific content and settings
- In VS Code, a `devcontainer.json` tells the editor how to access or create a development container
- The runtime can be a local container engine, Docker Compose stack, or some remote-compatible implementation

What it is not:

- Not a sandbox primitive
- Not a policy engine
- Not a guarantee of strong isolation by itself

Practical use here:

- Good UX layer for the existing sandbox on top of Docker, Podman, or VM-backed container hosts
- Useful as one frontend onto the backend abstraction, especially for IDE-based workflows
- The real security boundary still comes from the runtime and policy layers underneath

Update, September 2026:

- `documented`: the devcontainers CLI made lockfiles stable by default in 0.87, added WSLc support in 0.88, and added opt-in OCI auth hardening in 0.89
- `documented`: the spec exposes `privileged`, `capAdd`, `securityOpt`, and `runArgs` but no network-policy keys
- `documented`: Anthropic publishes a `claude-code` devcontainer feature that installs the latest CLI; the official `devcontainers/features` repo has `copilot-cli` and `github-cli` but no Claude, Codex, or Gemini features
- `documented`: Anthropic's reference devcontainer still uses an iptables and ipset firewall seeded from GitHub's `meta` ranges plus resolved A records for a fixed host list; the docs now call it a working example rather than a maintained base image and warn that skip-permissions mode plus a malicious repo can exfiltrate credentials from the config volume
- `documented`: Anthropic's "choose a sandbox environment" page ranks the Bash sandbox, `sandbox-runtime`, dev container, custom container, VM, and Claude Code on the web, requires a container, VM, or runtime for unattended runs, and names Docker Sandboxes as the microVM option

## Landscape reference: Nix and NixOS

Nix and NixOS fit best as an orthogonal layer, not as a primary sandbox category.

### Nix

Best fit:

- Reproducibility and image-definition layer
- Build and packaging substrate for any backend

What it gives you:

- Declarative definition of images, toolchains, policies, and helper binaries
- A build sandbox that isolates builds from the normal filesystem
- On Linux, private PID, mount, network, IPC, and UTS namespaces for sandboxed builds
- On macOS, support for sandboxed builds via the platform sandbox mechanism

What it does not give you:

- A complete interactive runtime sandbox for agent sessions
- A domain or URL-level outbound policy system
- A portable policy boundary for arbitrary third-party CLIs

Important limitation:

- Nix sandboxing is primarily a build-purity mechanism
- The Nix docs explicitly allow exceptions such as fixed-output derivations that need network access
- That makes it valuable for reproducible artifacts, but not sufficient as the main agent runtime boundary

Practical use here:

- Define and build base images for Docker, Podman, Kata, or VM guests
- Generate the proxy image and policy bundles reproducibly
- Build test matrices and golden environments for backend comparisons

### NixOS

Best fit:

- Declarative host OS or guest OS
- Image factory for VM and container backends
- Test harness for reproducible sandbox experiments

What it gives you:

- Declarative system config for firewalling, proxies, users, mounts, and services
- Official support for building system images
- Fast VM-based test workflows through NixOS tests
- Native NixOS containers and virtualization options

What it does not give you by itself:

- A stronger interactive agent sandbox than the runtime you choose underneath
- A reason to skip a proxy for outbound L7 policy

Important limitation:

- The NixOS manual warns that NixOS containers are not perfectly isolated from the host and should not be used for untrusted root users
- So `nixos-container` is not the right primary security boundary for hostile or semi-trusted agent workloads

Practical use here:

- Excellent choice for building immutable guest images for:
  - full VMs
  - microVMs
  - container hosts
- Strong choice for a dedicated sandbox appliance on Linux
- Useful for expressing the entire sandbox stack as code, even if the runtime remains Docker, Kata, or Firecracker

## Landscape reference: vendor-native agent sandboxes

Each major agent CLI now ships its own local sandbox or at least a permission model. These are OS-native sandbox wrappers in the taxonomy above, and they matter here for two reasons: they set the baseline users expect, and this project has to decide whether to nest them inside its container or disable them.

Evidence note for the September 2026 pass: Claude Code docs, the `sandbox-runtime` repo, and the Codex and Gemini CLI repos were read directly. Cursor, Factory Droid, Amp, JetBrains Junie, Kiro, and Windsurf have no reachable primary source from inside this sandbox and are marked `unknown` rather than filled in from memory.

### Claude Code sandboxed Bash and `sandbox-runtime`

Best fit:

- OS-native sandbox wrapper around one tool, not a whole-session boundary
- Reference design for host-side proxy plus in-sandbox placeholder secrets

What it is:

- `documented`: the sandbox wraps the Bash tool and its child processes only; file tools, MCP, and web fetch remain under the permission system
- `documented`: macOS uses Seatbelt; Linux and WSL2 use bubblewrap plus socat with an optional seccomp filter that blocks Unix sockets; native Windows is unsupported in Claude Code, while the standalone `srt` package has a Windows alpha built on a dedicated local user and Windows Filtering Platform egress fencing
- `documented`: the open-source `anthropic-experimental/sandbox-runtime` package (`srt`, Apache-2.0) is the same runtime exposed as a CLI and library
- `documented`: the Anthropic engineering post from October 2025 reports an 84 percent reduction in permission prompts from internal use

Filesystem model:

- `documented`: default write scope is the working directory, additional directories, and the session temp directory; default read scope is the whole machine minus denied paths, and the docs call out that `~/.aws/credentials` and `~/.ssh/` are readable by default
- `documented`: keys are `sandbox.filesystem.allowWrite`, `denyWrite`, `denyRead`, and `allowRead`, with wildcard denies such as `~/**/.env` honored inside broader allows
- `documented`: protected paths that cannot be exempted include `.claude` configuration, `.mcp.json`, shell rc files, `.gitconfig`, `.git/hooks`, and `.git/config`

Network model:

- `documented`: a proxy runs outside the sandbox; Linux traffic reaches it through a Unix-socket relay and macOS through localhost ports, with both HTTP and SOCKS5 listeners
- `documented`: no domains are allowed by default; first use prompts, and `network.allowedDomains`, `deniedDomains`, `strictAllowlist`, and `allowManagedDomainsOnly` turn prompting into deny-by-default policy
- `documented`: the default is hostname-only allowlisting from the client-supplied name with no TLS inspection; the docs warn about domain fronting and say TLS-aware isolation is under active development, and the `srt` README says system DNS is not fenced
- `documented`: `tlsTerminate` is an experimental MITM mode, and `httpProxyPort` and `socksProxyPort` plus `HTTPS_PROXY` in settings let the sandbox chain to an upstream proxy such as this repo's sidecar
- `documented`: `enableWeakerNestedSandbox` exists for running inside Docker without privileged namespaces and "considerably weakens security" according to the docs; `enableWeakerNetworkIsolation` opens macOS `trustd` for Go CLIs behind a custom CA and is described as an exfiltration vector

Secrets model:

- `documented`: `sandbox.credentials.files` and `envVars` support `deny` or `mask`; in `mask` mode commands see a per-session sentinel and the proxy substitutes the real value on egress only to `injectHosts`, which requires `tlsTerminate`
- `documented`: extras include regex extraction, JWT claim masking, SigV4 re-signing at the proxy, and an environment scrub for subprocesses; file masking is Linux-only and macOS denies the file instead
- `documented`: `mask` and `tlsTerminate` are ignored from repository-level settings, so a repo cannot weaken a user's posture

What it is not:

- Not a whole-session boundary; MCP servers and non-Bash tools are outside it
- Not TLS-inspecting by default, so no method or path policy
- Not a portable policy format; rules live in Claude settings scopes and `WebFetch(domain:...)` permission rules

Practical use here:

- The credential mask and sentinel design is the closest published analog to this repo's proxy-side secret injection and is worth aligning with, including host-scoped injection
- Running Claude Code inside this repo's container means either disabling the inner sandbox or accepting the documented weaker nested mode; that tradeoff should be stated in `docs/agents/claude.md`
- The `HTTPS_PROXY` chaining path is the supported way to keep the inner allowlist while forwarding through the sidecar

### Codex CLI sandbox, network proxy, and execpolicy

Best fit:

- OS-native sandbox wrapper with an optional managed MITM proxy
- Reference for method-level read-only egress and for a command-policy language

What it is:

- `documented` in the `codex-rs/linux-sandbox` README: bubblewrap is now the default Linux filesystem sandbox, with Landlock plus mount protections kept as a legacy path behind `features.use_legacy_landlock`; the earlier statement in this doc that Codex uses Landlock plus seccomp on Linux is stale
- `documented`: without a proxy the Linux sandbox unshares the network namespace; in managed proxy mode a TCP to Unix-socket bridge routes only to configured proxy endpoints and seccomp blocks new socket creation
- `documented`: writable roots are bind-mounted over a read-only rootfs, and `.git`, resolved `gitdir:` targets, and `.codex` are re-mounted read-only inside writable roots
- `unknown`: macOS Seatbelt details, the current `sandbox_mode` surface, and whether a native Windows sandbox shipped; the in-repo docs now redirect to the vendor site, which was unreachable

Network model:

- `documented` in the `codex-rs/network-proxy` README: an HTTP proxy on `127.0.0.1:3128` and SOCKS5 on `127.0.0.1:8081`, CONNECT tunneling, and optional TLS termination with a managed CA exposed to child processes through environment variables
- `documented`: a `limited` mode allows only GET, HEAD, and OPTIONS and requires MITM for HTTPS; a domain table maps patterns to allow or deny; hostnames resolving to private IPs are blocked even when allowlisted; SOCKS5 UDP is blocked
- `inferred`: the `[permissions.*.network]` table shape in the crate README suggests a newer config layout than the `sandbox_workspace_write.network_access` key cited earlier in this doc; the user-facing reference was not verified

Command policy:

- `documented`: `execpolicy` uses Starlark `.rules` files with `prefix_rule` entries carrying a pattern, a decision of `allow`, `prompt`, or `forbidden`, and optional `match` and `not_match` examples; `codex execpolicy check` evaluates a command and the strictest decision across matches wins

Secrets model:

- `unknown`: nothing in the fetched crate READMEs addresses credential scrubbing or injection

What it is not:

- Not a container or VM boundary
- Not agent-agnostic; configuration lives in Codex TOML

Practical use here:

- The `limited` read-only egress mode is a one-line policy primitive this repo could expose per host
- Blocking allowlisted hostnames that resolve to private ranges is a cheap protection the sidecar should adopt
- `execpolicy` is a useful comparison point for any future command-level rules alongside Cedar and Rego

### Gemini CLI sandbox and policy engine

Best fit:

- Container-first vendor sandbox with a gVisor option
- Reference for a tiered tool-call policy engine

What it is:

- `documented`: `GEMINI_SANDBOX` accepts `docker`, `podman`, `sandbox-exec`, `runsc`, and `lxc`, and the configuration reference now labels whole-process sandboxing legacy in favor of `security.toolSandboxing`, which isolates individual shell and write-file executions
- `documented`: a Windows native sandbox section exists, mechanism not described in the fetched docs
- `documented`: the gVisor path runs `docker run --runtime=runsc` and is described as the strongest available isolation
- `documented`: macOS Seatbelt profiles are `permissive-open`, `permissive-proxied`, `restrictive-open`, `restrictive-proxied`, `strict-open`, and `strict-proxied`
- `documented`: custom sandbox images via `.gemini/sandbox.Dockerfile`, plus `SANDBOX_FLAGS`, `SANDBOX_MOUNTS`, and `SANDBOX_SET_UID_GID`

Network model:

- `documented`: `tools.sandboxNetworkAccess` is a boolean that defaults to false; no domain allowlist is documented
- `unknown`: how the `*-proxied` Seatbelt profiles reach a proxy, and whether the earlier `GEMINI_SANDBOX_PROXY_COMMAND` variable still exists

Policy engine:

- `documented`: TOML rules under `~/.gemini/policies/` plus an admin tier under system paths; fields include `toolName` with wildcards, `decision` of `allow`, `deny`, or `ask_user`, `priority`, `argsPattern`, `commandPrefix`, `commandRegex`, `modes`, `mcpName`, and `toolAnnotations`; admin rules outrank user, workspace, extension, and default tiers

Practical use here:

- Gemini composes naturally with an external image and proxy because its default sandbox is already a container
- The admin-locked policy tier is the pattern to copy if this repo ever ships organization-managed policy

### Permission-only agents

- `documented`: GitHub Copilot CLI's README describes approval before every action and no sandbox or network restriction
- `documented`: OpenCode exposes a per-tool `permission` object with `allow`, `ask`, or `deny`, wildcard patterns, last match wins, and per-agent overrides, but no sandbox or network restriction
- `documented`: Hermes Agent has no native sandbox and instead offers terminal backends for local, Docker, SSH, Singularity, Modal, Daytona, and Vercel Sandbox execution plus command approval patterns
- `documented`: Pi states it has no built-in permission system for filesystem, process, network, or credential access and points users to an external micro-VM extension, Docker, or OpenShell
- `documented`: Zed's agent settings do not mention sandboxing; its tool permissions live in a separate doc that was not read
- `unknown`: Cursor, Factory Droid, Amp, JetBrains Junie, Kiro, and Windsurf

Practical use here:

- Permission-only agents gain the most from an external sandbox, which is this repo's core case
- Agents that offer their own container backends, such as Hermes, are candidates for pointing at this repo's image instead of a generic one

### Cross-cutting observations

- Claude Code and Codex have converged on the same Linux design: bubblewrap, a network namespace, Unix-socket bridging to a host-side HTTP and SOCKS5 proxy, and seccomp to stop new sockets, with hostname-only allowlisting by default and optional TLS termination
- Both vendors document the same holes: unfenced DNS, domain fronting, Unix-socket escalation through `docker.sock`, and weakened modes inside unprivileged containers
- This repo's always-MITM sidecar sits at the strict end of that spectrum, which is the right differentiation as long as the CA distribution and Go-CLI TLS caveats are documented
- Nesting a vendor sandbox inside this repo's container is now a real configuration question for Claude Code and Codex rather than a hypothetical

## Potential architecture directions

### Backend abstraction layer

Create a runtime interface with pluggable backends:

- `container`
- `gvisor`
- `kata`
- `microvm`
- `full-vm`
- `os-native`

Keep policy and logging above this interface where possible.

### Policy compiler

Define one high-level policy model and compile it to backend-specific controls:

- Proxy rules
- Landlock rules
- Seccomp profile
- Container runtime settings
- Cilium policy

This is likely the most important architecture move if multi-agent portability is the real goal.

### MCP gateway and host-side registry

This is a separate but closely related control-plane problem.

See:

- [mcp-gateway.md](./mcp-gateway.md)

Why it matters:

- it lets MCP auth outlive ephemeral agent containers
- it creates a separate network-policy surface for OAuth-heavy MCP flows
- it provides a path to host-managed local MCP server lifecycle

### Split trusted controller from untrusted worker

The controller should live outside the sandbox and own:

- Policy loading
- Approval handling
- Event logging
- Credential brokering
- Runtime lifecycle

The worker should only run agent commands.

### Ephemeral execution with durable workspace

Use ephemeral runtime instances per task or session, but keep durable state only in:

- The shared workspace
- Explicit per-agent state volumes
- External credential brokers

This lowers persistence risk and makes stronger backends easier to adopt.

### High-assurance writeback mode

For sensitive repos, consider a mode where the agent does not get direct write access to the workspace mount. Instead it writes patches or a shadow worktree, and a trusted controller applies the changes.

This is higher friction, but it creates a much stronger security boundary than direct bind mounts.

### Placeholder secrets and credential masking

Proxy-side substitution of placeholder values is now implemented independently by Claude Code, Docker Sandboxes, OpenSandbox, Deno Sandbox, BoxLite, microsandbox, nono, Infisical Agent Vault, iron-proxy, and airut. The strongest variants add:

- host-scoped injection so a placeholder is only redeemed for approved hosts
- a surface allowlist that names where substitution may occur: headers, query, path, body, or websocket frames
- re-signing for signature-based schemes such as AWS SigV4
- refusal to honor mask rules from repository-level settings

This repo's `m15` and `m17` work already sits in this space; the missing pieces are the surface allowlist and re-signing.

### DNS as a control plane

Two postures are in use:

- allow DNS and block transport, as in this repo's firewall, Claude Code, and Anthropic's reference devcontainer
- answer every DNS query with a dummy address so nothing resolves except through the proxy, as in Coder Boundary, httpjail's strong mode, airut, iron-proxy, and Docker Sandboxes' internal resolver

AWS documented DNS exfiltration from its own sandbox network mode, and the Codex proxy docs say DNS rebinding needs lower-layer enforcement. If DNS exfiltration enters the threat model, the sinkhole posture composes cleanly with the existing iptables plus proxy design.

### Capability declaration with fail-closed validation

Harbor's environment contract pairs a typed network policy with a per-backend capability declaration and rejects a run when a backend cannot enforce a requested entry type. Adopting that shape for the backend interface turns "capabilities can degrade by backend" into an explicit, testable contract rather than a documentation promise.

### Semantic service rules

Anthropic's GitHub proxy enforces push only to the current branch, repository scope, and a pinned GraphQL operation set; wirenboard/agent-vm derives a repository allowlist from `git remote` and rejects off-list pushes at the proxy. These go beyond host and path matching toward service-aware rules. This repo's `services.github` model in `m18` is the same direction and should be described that way.

### Nested vendor sandboxes

Claude Code and Codex now bring their own sandbox and proxy. Three options exist for each agent image: disable the inner sandbox, run it in its documented weaker nested mode, or run it fully and chain its proxy to the sidecar. The choice affects CA distribution, Unix-socket access, and which layer reports a denial. It should be a per-agent documented setting.

### No-NIC transport with a host broker

The companion architecture doc proposes a strict mode in which the guest has no general-purpose network interface at all. A guest-side shim sends proxy requests over vsock to a host broker, name resolution happens outside the guest, and only broker-supported protocols exist. Direct TCP, UDP, ICMP, QUIC, DNS, link-local, and private-network access are then structurally absent rather than filtered. Matchlock already uses vsock for exec and its VFS but keeps a NIC; Docker Sandboxes keeps a NIC and filters. This is the strongest egress posture in the landscape and the hardest on tool compatibility; SSH Git and arbitrary network tools would need rewriting to HTTPS or a declared TCP capability.

### Authority-scoped capabilities

Keeping a secret outside the guest is not the same as limiting what the guest can do with it. The companion doc frames each egress rule as a capability that bundles destination, request shape, credential placement, and limits such as redirect handling, request and response byte caps, rate, lifetime, and whether bodies may pass. Anthropic's GitHub proxy and wirenboard/agent-vm are partial implementations of the same idea for one service. This extends `Semantic service rules` above and argues for a `limits` layer in the policy model.

### Workspace modes

The companion doc names four modes, which sharpen `High-assurance writeback mode` above:

- import a content-addressed snapshot into a private writable overlay and export a validated patch plus manifest, as the default
- `read-only-source`: an immutable source tree plus a private working clone, which is Docker Sandboxes' `--clone`
- `live-workspace`: direct read and write sharing, labeled lower assurance, which is this repo's current default and Docker Sandboxes' default
- `artifact-only`: no source export, with named build artifacts retrieved through the broker

brood-box's reviewed, hash-verified flush is a working implementation of the default mode's export step.

### Shared kernel between agent and enforcement point

The companion doc's central critique of the current design is that the agent container and the trusted proxy sidecar share Colima's guest kernel, so a container escape lands on the machine that enforces egress and holds credentials. `Split trusted controller from untrusted worker` above already argues for moving the controller out; the critique adds that on macOS the controller must leave the Colima VM, not just the container, for the boundary to change.

## Research backlog: open-source comparables

These should be treated as adjacent or comparable systems when building the backend matrix and feature inventory.

For each project, review:

- Filesystem model
- Network enforcement model
- Credential handling
- Secret injection or redaction
- Logging and auditability
- Patch, branch, or output handoff model
- Multi-agent support
- Local versus remote deployment model

### Status changes since March 2026

- `documented`: `AshitaOrbis/agent-embassy` is archived; its README says the layers it combined do not form a containment primitive and points to Docker Sandboxes and AISI's sandboxing toolkit
- `documented`: `textcortex/claude-code-sandbox` is archived in favor of a Kubernetes orchestrator called Spritz
- `documented`: `zerocore-ai/microsandbox` now lives at `superradcompany/microsandbox`
- `documented`: `daytonaio/daytona` is no longer maintained; core development moved to a private codebase in June 2026
- `documented`: `kubernetes-sigs/agent-sandbox` remains `v1beta1` with network policy still exploratory; `alibaba/OpenSandbox` gained a secure-runtime option for gVisor, Kata, and Firecracker, a DNS plus nftables egress sidecar, and a Credential Vault
- No archive or deprecation notice was found for `matchlock`, `leash`, `agent-infra/sandbox`, `release-engineers/agent-sandbox`, `safeyolo`, `claudebox`, `sandcat`, `claude-code-safety-net`, `openclaw-deploy`, or `tsk`; activity metrics could not be captured in this pass

### Direct or near-direct comparables

- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
  - Kubernetes SIG Apps project defining a `Sandbox` CRD and controller for isolated, stateful, singleton workloads with stable identity, persistent storage, lifecycle management, templates, claims, and warm pools
  - Review focus: declarative API shape, CRD model, controller lifecycle, stable identity semantics, pause and resume behavior, warm-pool strategy, and how runtime isolation is delegated to pluggable runtimes such as gVisor or Kata

- [alibaba/OpenSandbox](https://github.com/alibaba/OpenSandbox)
  - General-purpose sandbox platform with multi-language SDKs, unified sandbox APIs, Docker and Kubernetes runtimes, ingress and egress components, and optional secure runtimes including gVisor, Kata, and Firecracker
  - Review focus: protocol and API design, lifecycle server model, runtime abstraction, secure-runtime pluggability, the `networkPolicy` shape with `defaultAction` and egress targets, the DNS plus nftables egress sidecar, the Credential Vault's transparent mitmproxy, and how local Docker mode differs from Kubernetes mode

- [jingkaihe/matchlock](https://github.com/jingkaihe/matchlock)
  - Experimental CLI and SDK for running AI agents in ephemeral microVMs with host-managed network allowlisting, MITM-based secret injection, and isolated overlay-backed filesystem snapshots
  - Review focus: microVM lifecycle and startup model, host-side secret boundary, allowlist and interception design, volume snapshot semantics, and Linux versus Apple Silicon portability

- [strongdm/leash](https://github.com/strongdm/leash)
  - Multi-agent sandbox that wraps agents in containers, applies Cedar-defined policy, and combines cgroup-scoped eBPF monitoring with an HTTP MITM proxy plus an experimental native macOS mode
  - Review focus: Cedar-to-runtime compilation, Record, Shadow, and Enforce workflow, eBPF plus proxy control-plane split, MCP policy surface, and Linux versus macOS capability degradation

- [coder/boundary](https://github.com/coder/boundary)
  - `documented`: MIT Go CLI that runs one command with default-deny HTTP and HTTPS egress through a transparent MITM proxy, rules of the form `method`, `domain`, and `path` with wildcards and segment-based path matching, a YAML config, and audit logs that feed Coder workspaces; the default `nsjail` backend uses a network namespace, veth, iptables redirect, and a dummy DNS server to stop DNS exfiltration and needs `CAP_NET_ADMIN`; the `landjail` backend uses Landlock plus advisory proxy environment variables; Linux only, no secrets model
  - Review focus: rule grammar versus this repo's policy schema, the DNS sinkhole, the capability escalation path, and what a macOS story would require
  - Verdict: `likely core reference` for the L7 rule model

- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell)
  - `documented`: Apache-2.0 alpha combining a gateway, a sandbox runtime on Docker or Podman with optional microVM or Kubernetes compute drivers, a YAML policy engine with `filesystem_policy`, best-effort Landlock, process restrictions, and `network_policies` whose endpoints carry host, port, protocol, enforcement mode, `read-only` access presets, and a per-binary scope; policies hot-reload; secrets are injected as environment variables at runtime and the inference path swaps caller credentials for backend credentials at the proxy; Linux, Apple Silicon, and experimental WSL2; base images for Claude Code, OpenCode, Codex, and Copilot CLI
  - Review focus: the policy schema, whether the L7 proxy is transparent or explicit and whether it terminates TLS, the per-binary network scope, and the cost of its gateway and Kubernetes surface for a local tool
  - Verdict: `likely core reference` as the closest open-source project to this repo's shape

- [nolabs-ai/nono](https://github.com/nolabs-ai/nono)
  - `documented`: Apache-2.0 Rust CLI at 0.75.0 as of 2026-09-01 that runs agents under Landlock on Linux and Seatbelt on macOS with no daemon, container, or VM; signed profiles from a registry for Claude Code, Codex, Pi, Copilot, Hermes, OpenCode, and OpenClaw; per-tool child sandboxes through a broker; a credential proxy where the agent holds placeholder tokens redeemed by the proxy and each credential carries an `endpoint_policy` of allowed methods and paths; macOS, Linux, and WSL2
  - Review focus: per-credential endpoint policy as a policy IR fragment, placeholder redemption, the per-tool broker, and whether seccomp is used
  - Verdict: `likely core reference` for policy and credential design, `os-native` boundary only

- [TencentCloud/CubeSandbox](https://github.com/TencentCloud/CubeSandbox)
  - `documented`: Apache-2.0 sandbox service at 0.7.0 (August 2026) running each sandbox in its own KVM microVM with a dedicated kernel on x86_64 and ARM64 Linux; components are a hypervisor manager, a containerd shim, an eBPF virtual switch for L3 and L4 policy, and CubeEgress, a per-host transparent L7 egress proxy reached through eBPF packet marking and iptables TPROXY on ports 8080 and 8443
  - `documented`: CubeEgress terminates TLS with an embedded CA, matches `scheme`, `port`, `sni` with wildcards, `host`, a `method` list, and exact or prefix `path`, injects headers from operator-side secrets through `${SECRET}` placeholders, and writes JSONL audit records for requests, security events, and TLS handshake failures with secrets redacted; documented limits are that internal cluster traffic bypasses the proxy, unmatched TCP and UDP falls to L3 and L4 policy, and images built without the CA fail HTTPS
  - `documented`: a control plane with a REST gateway, orchestrator, and reverse proxy; cross-node pause and resume; Kubernetes deployment in preview
  - Review focus: the rule grammar against this repo's policy schema, eBPF steering with TPROXY as a transparent alternative to iptables REDIRECT, the audit record schema, and how much of the control plane a local tool would need
  - Verdict: `likely core reference` for a cloud L7 data plane; Linux-only and cluster-oriented

- [stacklok/brood-box](https://github.com/stacklok/brood-box)
  - `documented`: Apache-2.0 experimental Go CLI running agents in libkrun microVMs on Linux KVM or Apple Silicon; copy-on-write workspace snapshots via reflink, virtio-fs mount, an interactive per-file diff review before a hash-verified flush back with setuid stripping and non-negotiable exclusions for `.env`, key files, `.ssh`, and `.aws`; DNS-aware egress firewall with `permissive`, `standard`, and `locked` profiles and `--allow-host host:port`; per-workspace config cannot widen egress; env forwarding by name or glob plus git token and SSH agent forwarding; images for Claude Code, Codex, OpenCode, Hermes, and Gemini CLI; MCP proxying from ToolHive
  - Review focus: the review-before-writeback workspace model against this doc's high-assurance writeback idea, egress profiles, and the libkrun VMM confinement
  - Verdict: `likely core reference` as the closest agent-agnostic microVM CLI in spirit

- [airutorg/airut](https://github.com/airutorg/airut)
  - `documented`: MIT self-hosted service that runs Claude Code per conversation in rootless Podman with all capabilities dropped; all HTTP and HTTPS is transparently routed through mitmproxy enforcing an allowlist read from the repo's default branch so the agent cannot edit it; a custom DNS responder answers the proxy IP for every query and never forwards upstream; masked secrets with surrogate tokens swapped by host scope, AWS SigV4 re-signing, GitHub App installation tokens with GraphQL repo scoping, and git credentials decoded by the proxy
  - Review focus: the mitmproxy plus DNS-sinkhole architecture, the surrogate secret model, and the policy-from-default-branch trick
  - Verdict: `likely core reference` for the proxy layer, Claude-only and channel-driven

- [ironsh/iron-proxy](https://github.com/ironsh/iron-proxy)
  - `documented`: Apache-2.0 Go single binary and Docker image; a MITM egress proxy with a built-in DNS server so every name resolves to the proxy, TLS terminated with your CA, an optional explicit tunnel listener, a default-deny domain and CIDR allowlist, an upstream IP deny list against metadata and loopback rebinding, an ordered transform pipeline, per-request JSON audit, secrets swapped from proxy tokens in header, query, path, and body, WebSocket and SSE support, and a PostgreSQL MITM mode; Linux and macOS binaries; first release April 2026 per a curated list
  - Review focus: DNS design, audit-log format, the transform pipeline, and whether method or path rules exist
  - Verdict: `likely core reference` for proxy and DNS design

- [Infisical/agent-vault](https://github.com/Infisical/agent-vault)
  - `documented`: MIT core with an enterprise directory; an explicit `HTTPS_PROXY` MITM credential broker designed to run on a separate machine; services matched by host pattern with bearer, basic, API-key, custom-header, and passthrough auth types; placeholders substituted only in operator-listed surfaces across path, query, header, body, and websocket; default pass-through for unmatched hosts with a strict deny option; request logging; macOS and Linux installers
  - Review focus: the per-surface substitution allowlist and how a separate broker machine changes the trust model
  - Verdict: `useful supporting reference` for credential brokering

- [coder/httpjail](https://github.com/coder/httpjail)
  - `documented`: CC0 experimental proxy jail with rules as JavaScript expressions over host and method, shell scripts, or a JSON line-processor; TLS interception; a Docker run mode on Linux; a Linux strong mode that answers every DNS query with a dummy address so queries never leave; macOS weak mode without DNS interception
  - Review focus: the DNS sinkhole and the rule-as-code model
  - Verdict: `useful supporting reference`

- [superradcompany/microsandbox](https://github.com/superradcompany/microsandbox)
  - `documented`: Apache-2.0 libkrun-based microVMs from OCI images with an `msb` CLI, SDKs, an MCP server, and agent skills; `network: none` or `allowed_hosts` plus `allowed_ports` for default-deny egress enforced host-side; the guest receives placeholders and the host proxy substitutes real values only for the allowed TLS hostname; macOS Apple Silicon, Linux KVM, Windows WHP; beta at 0.6.17
  - `documented`: the filesystem is a layered root of read-only cached image layers plus a private per-sandbox writable layer; host directories are exposed live over virtio-fs through a trusted broker that enforces containment with `openat2` and `RESOLVE_BENEATH` on Linux 5.6+, read-only mounts are enforced host-side so even a privileged guest cannot write through them, host uid and gid are hidden by default, and snapshots capture the writable layer plus a manifest pinning the base image with optional integrity hashes off by default; digest checks do not verify signatures or provenance
  - `companion doc`: DNS-rebinding protection is reported in the network policy implementation; not read here
  - Review focus: host-side netstack enforcement, placeholder secrets, and snapshot semantics
  - Verdict: `useful supporting reference`

- [boxlite-ai/boxlite](https://github.com/boxlite-ai/boxlite)
  - `documented`: Apache-2.0 embeddable, daemonless microVM runtime at 0.10.0 built on libkrun with seccomp on Linux and `sandbox-exec` on macOS wrapped around the VMM, per-box QCOW2 copy-on-write disks, ro and rw volume mounts, clone and export, an `allow_net` egress allowlist, and secret placeholders that never enter the VM; macOS Apple Silicon, Linux, WSL2, Intel Mac not yet
  - Review focus: VMM confinement, the library-first API, and egress granularity
  - Verdict: `useful supporting reference`

- [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
  - `documented`: Apache-2.0 `srt` package at 0.0.75 that wraps any command in Seatbelt on macOS or bubblewrap plus optional seccomp on Linux, with a host-side HTTP and SOCKS5 proxy, a domain allowlist, optional TLS termination, credential masking, and an alpha Windows mode; see the vendor-native section for the full model
  - Review focus: reuse as the `os-native` backend and its settings schema as a compile target
  - Verdict: `likely core reference` for an `os-native` backend

- [agent-infra/sandbox](https://github.com/agent-infra/sandbox)
  - All-in-one Docker sandbox with browser, shell, file, MCP, VS Code Server, and Jupyter in one container
  - Review focus: single-container unified environment, browser and MCP primitives, API surface, and what security guarantees are actually enforced versus claimed

- [release-engineers/agent-sandbox](https://github.com/release-engineers/agent-sandbox)
  - Container-per-agent approach with a dedicated network and HTTP(S) proxy, plus patch-file writeback to the original repo
  - Review focus: copy-on-write repo model, diff-based handoff, domain allowlist proxy, and hook integration

- [craigbalding/safeyolo](https://github.com/craigbalding/safeyolo)
  - Secure sandbox for Claude Code and Codex with network isolation, credential protection, and audit logging
  - Review focus: policy model, credential isolation approach, audit log design, and whether it is runtime-portable across agents

- [numtide/claudebox](https://github.com/numtide/claudebox)
  - Lightweight sandbox for Claude Code with a shadowed `$HOME`, Nix integration, Linux-first support, and macOS marked experimental
  - Review focus: OS-native versus Nix-based primitives, credential isolation by home shadowing, and mount layout choices

- [AshitaOrbis/agent-embassy](https://github.com/AshitaOrbis/agent-embassy)
  - Archived. Docker Compose sandbox with egress proxy, no host filesystem access, inbox/outbox directories, and host-side output validation
  - Review focus: the embassy pattern and output-validation boundary remain useful ideas even though the project is closed

- [VirtusLab/sandcat](https://github.com/VirtusLab/sandcat)
  - Docker and devcontainer setup using transparent mitmproxy, WireGuard-based traffic capture, host allowlists, and proxy-side secret substitution
  - Review focus: transparent proxy architecture, secret-injection design, WireGuard requirement, DNS and non-HTTP handling, and developer UX

- [inoio/agents-sandbox](https://github.com/inoio/agents-sandbox)
  - `documented`: GPL-3.0 Go tool running agents in a hypervisor VM on Linux KVM or Apple Silicon with `/workspace` mounted read-write, secrets injected as environment at runtime, egress and ingress profiles with allow and deny lists, and a runner image built from a Dockerfile; agents OpenCode, Pi, and Claude
  - Review focus: the profile model; the GPL license limits reuse
  - Verdict: `useful supporting reference`

- [wirenboard/agent-vm](https://github.com/wirenboard/agent-vm)
  - `documented`: MIT Rust rewrite on a patched microsandbox fork, Linux KVM only; a TLS-intercepting proxy substitutes a real OAuth bearer for a placeholder and handles token refresh; a per-launch GitHub repository allowlist is derived from `git remote` and off-list pushes get a 403 at the proxy; Claude Code, Codex, and OpenCode
  - Review focus: repository-scoped GitHub filtering, which mirrors this repo's `services.github` model
  - Verdict: `useful supporting reference`

- [mensfeld/code-on-incus](https://github.com/mensfeld/code-on-incus)
  - `documented`: MIT Go tool using Incus system containers with nftables isolation in restricted, allowlist, and open modes, DNS pinning, per-host port controls, kernel-level threat detection with auto-pause or kill, and headless prompt runs; Linux native, macOS via Colima or Lima; Claude Code, Codex, OpenCode, Pi
  - Review focus: L3 and L4 policy plus active response; no L7 proxy
  - Verdict: `useful supporting reference`

- [stefanoginella/aicontainer](https://github.com/stefanoginella/aicontainer)
  - `documented`: MIT devcontainer for Claude Code, Codex, and OpenCode with the Docker socket behind a digest-pinned socket proxy, all capabilities dropped, an opt-in outbound allowlist file, an always-on link-local and cloud-metadata block, no host credentials or SSH agent, and a hook that blocks `.env` reads and piped installers; network is open by default
  - Review focus: container hardening details worth copying into the base image
  - Verdict: `useful supporting reference`

- [node9-ai/node9-proxy](https://github.com/node9-ai/node9-proxy)
  - `documented`: Apache-2.0 hook and MCP-gateway policy engine with bash AST analysis plus a sandbox mode that generates a Dockerfile with an ipset and iptables deny-by-default egress wall and scoped mounts; the agent still holds its own credentials; Claude first
  - Review focus: combining hook policy with kernel egress
  - Verdict: `useful supporting reference`

### Adjacent but important references

- [kenryu42/claude-code-safety-net](https://github.com/kenryu42/claude-code-safety-net)
  - Plugin and hook layer that blocks destructive git and filesystem commands before execution
  - Review focus: command interception rules, audit logging, strict and paranoid modes, and how hook-based safeguards complement or fail to replace runtime sandboxing

- [schmitthub/openclaw-deploy](https://github.com/schmitthub/openclaw-deploy)
  - Remote deployment of OpenClaw gateway fleets with Envoy egress filtering, Tailscale networking, and CoreDNS allowlist proxying
  - Review focus: remote gateway architecture, structured egress policy, DNS exfiltration prevention, SSH and raw TCP handling, and hosted deployment tradeoffs

- [dtormoen/tsk](https://github.com/dtormoen/tsk)
  - Task orchestration tool that runs Claude and Codex in parallel sandbox containers, auto-builds toolchain images, and fetches branches back for review
  - Review focus: task queueing, multi-agent abstraction, branch-based handoff, automatic image construction, and Docker versus Podman runtime support

- [eqtylab/cupcake](https://github.com/eqtylab/cupcake)
  - `documented`: Apache-2.0 policy engine that compiles OPA Rego to Wasm and evaluates it in agent hooks for Claude Code, Cursor, Factory, and OpenCode with allow, modify, block, warn, and require-review decisions; not a runtime boundary
  - Review focus: a hook-layer complement to egress policy, and Rego ergonomics for the policy IR question

- [stacklok/toolhive](https://github.com/stacklok/toolhive)
  - `documented`: Apache-2.0 tool that runs MCP servers in containers with permission profiles whose `network.outbound` section allows hosts and ports or everything, enforced in bridge mode by two Squid proxies with an experimental Envoy replacement; host and port granularity only
  - Review focus: sidecar egress for MCP servers; belongs with the MCP gateway track

- [Zouuup/landrun](https://github.com/Zouuup/landrun)
  - `documented`: MIT Go CLI wrapping Landlock up to ABI 9 with read, execute, and write path rules, TCP bind and connect port rules, IPC scoping, and audit logging; packaged in Ubuntu 26.04 and Debian
  - Review focus: an in-container Landlock layer beneath the iptables rules

- [dagger/container-use](https://github.com/dagger/container-use)
  - `documented`: Apache-2.0 experimental MCP server giving each agent a Dagger-managed container on its own git branch; no network policy documented; archive status could not be verified
  - Review focus: the branch-per-environment workspace model only

- [rivet-dev/sandbox-agent](https://github.com/rivet-dev/sandbox-agent)
  - `documented`: Apache-2.0 single static binary installed inside any sandbox that exposes an HTTP and SSE API with a universal session schema for Claude Code, Codex, OpenCode, Cursor, Amp, and Pi; not an isolation tool
  - Review focus: event schema for a headless control API

- [abshkbh/arrakis](https://github.com/abshkbh/arrakis)
  - `documented`: AGPL-3.0 self-hosted REST server, CLI, SDK, and MCP server spawning Cloud Hypervisor microVMs with snapshot and restore and VNC; Linux KVM only; no egress policy
  - Review focus: snapshot and restore only

- [thevibeworks/claude-code-yolo](https://github.com/thevibeworks/claude-code-yolo), [nikvdp/cco](https://github.com/nikvdp/cco), [RchGrav/claudebox](https://github.com/RchGrav/claudebox), [cleatdev/cleat](https://github.com/cleatdev/cleat), [ashishb/amazing-sandbox](https://github.com/ashishb/amazing-sandbox), [katspaugh/machine](https://github.com/katspaugh/machine)
  - Docker, Seatbelt, bubblewrap, or Lima wrappers with permissions off and at most a boolean or per-project host allowlist for network; low relevance beyond their multi-agent config-home layouts

- [confidential-containers/confidential-containers](https://github.com/confidential-containers/confidential-containers)
  - `documented`: a project using trusted execution environments to protect containers and data from the cloud provider, deployed with Helm charts; the companion doc adds that it builds on Kata plus AMD SEV-SNP and Intel TDX with a Trustee key broker and attestation services (`companion doc`, not read here)
  - Review focus: relevant only for a future hosted tier where the cloud operator is outside the trust boundary; it does not address egress, and an attested malicious workload can still leak over an allowed channel

- [UKGovernmentBEIS/aisi-sandboxing](https://github.com/UKGovernmentBEIS/aisi-sandboxing)
  - Inspect-oriented sandboxing toolkit with Docker Compose, Kubernetes, and Proxmox plugins plus a sandboxing protocol document; low relevance as a developer CLI, but its tooling, host, and network isolation taxonomy is a good framing

## Research worksheet

Use this worksheet for every repo, product, or runtime under review.

### Evidence standard

- Prefer primary docs over blog posts and secondary summaries.
- Mark every claim as `documented`, `inferred`, or `unknown`.
- If the runtime boundary is not explicit, do not guess silently.
- Capture one or two source links for every non-obvious claim.

### Worksheet fields

- Item name
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
  - tooling layer
- Research priority:
  - P0
  - P1
  - P2
- Claimed runtime boundary
- Verified runtime boundary
- Workspace model
- Persistence model
- Network control model
- Runtime control model
- Secrets model
- Observability model
- Local platform support
- Multi-agent compatibility
- Key strengths
- Key limits
- Open questions
- Verdict:
  - likely core reference
  - useful supporting reference
  - low relevance

### Primitive checklist

When reviewing an item, capture whether it implements any of these primitives:

- Shared workspace mount
- Copy-on-write workspace
- Patch-only or branch-only writeback
- Read-only parent or host mounts
- Home-directory shadowing
- Scratch or temp volume isolation
- Domain allowlist proxy
- Path and method policy
- Transparent versus explicit proxying
- DNS allowlist or DNS interception
- Non-HTTP TCP policy
- SSH handling
- Secret brokering
- Proxy-side secret substitution
- Output validation and quarantine
- Audit logs
- Command hooks or deny rules
- Multi-agent abstraction
- Remote execution or gateway fleet support

## Research notes

### VirtusLab/sandcat

- Item name: `VirtusLab/sandcat`
- Category:
  - proxy or policy layer
  - tooling layer
- Research priority: `P2`
- Claimed runtime boundary:
  - `documented`: Docker and devcontainer setup with transparent mitmproxy, host-mounted settings, and proxy-side secret substitution
- Verified runtime boundary:
  - `documented`: plain Docker containers, not a VM, microVM, or alternate kernel boundary
  - `documented`: the `app` container shares the `wg-client` container's network namespace via `network_mode: "service:wg-client"`
  - `documented`: `wg-client` owns `NET_ADMIN`, creates the WireGuard tunnel, and installs iptables kill-switch rules
  - `documented`: mitmproxy runs in WireGuard mode via `mitmweb --mode wireguard`
- Workspace model:
  - `documented`: bind-mounted project workspace
  - `documented`: `.devcontainer` is overlaid read-only so the agent cannot rewrite its own compose files, Dockerfile, or devcontainer config
- Persistence model:
  - `documented`: named `app-home` volume persists the devcontainer user's home and agent state across rebuilds
- Network control model:
  - `documented`: all app traffic is routed through the `wg-client` namespace and WireGuard tunnel, so tools do not need explicit proxy environment variables
  - `documented`: network rules are ordered, first-match-wins, default deny, and match `host` plus optional HTTP `method`
  - `documented`: direct `eth0` egress, direct host access, and direct access to the mitmproxy container are intentionally blocked by the kill switch
  - `inferred`: actual policy enforcement is implemented in the mitmproxy addon's `request(self, flow: http.HTTPFlow)` hook, so the repo shows HTTP(S) policy decisions clearly but does not show an equivalent policy engine for DNS or arbitrary raw TCP or UDP
- Runtime control model:
  - `documented`: capability separation is thoughtful but limited; only the networking container gets `NET_ADMIN`, while app containers inherit its namespace without that capability
  - `unknown`: no documented seccomp, AppArmor, SELinux, gVisor, or similar stronger runtime boundary
- Secrets model:
  - `documented`: real secrets live only in host-side settings mounted into mitmproxy
  - `documented`: the app container receives deterministic placeholders through `sandcat.env`
  - `documented`: the addon replaces placeholders in request URL, headers, and body only for allowed hosts and blocks mismatches as secret leaks
- Observability model:
  - `documented`: mitmweb UI plus addon warning logs
  - `unknown`: no structured audit event schema or external policy-decision stream is documented
- Local platform support:
  - `documented`: Docker Compose plus VS Code devcontainer workflow
  - `inferred`: should work anywhere Docker-based devcontainers work
  - `unknown`: no explicit support matrix for macOS, Linux, or Apple Silicon
- Multi-agent compatibility:
  - `documented`: packaged workflow is Claude-centric
  - `inferred`: network and secret primitives are generic enough to reuse for other agents, but that is not the repo's primary surface
- Primitive checklist:
  - Shared workspace mount: yes
  - Copy-on-write workspace: no
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: yes
  - Home-directory shadowing: partial
  - Scratch or temp volume isolation: no explicit model
  - Domain allowlist proxy: yes
  - Path and method policy: method only, no path support
  - Transparent versus explicit proxying: transparent
  - DNS allowlist or DNS interception: interception is documented, policy model is unknown
  - Non-HTTP TCP policy: tunnel path is documented, policy model is unknown
  - SSH handling: effectively disabled; GitHub SSH remotes are rewritten to HTTPS
  - Secret brokering: yes
  - Proxy-side secret substitution: yes
  - Output validation and quarantine: no
  - Audit logs: partial
  - Command hooks or deny rules: no
  - Multi-agent abstraction: no
  - Remote execution or gateway fleet support: no
- Key strengths:
  - Transparent capture avoids the "`HTTP_PROXY` is advisory" problem and works for tools that ignore explicit proxy settings
  - Proxy-side secret substitution is one of the strongest ideas here; the agent sees placeholders, not raw API keys
  - Devcontainer hardening is concrete and useful: cleared forwarded credential env vars, post-start socket cleanup, copied git config disabled, workspace trust enabled, and local terminal disabled
- Key limits:
  - This is not a new runtime substrate. It is still a standard Docker container boundary with better network plumbing
  - Policy expressiveness is still narrow: host plus optional method, no path rules, no backend-agnostic policy IR, no explicit non-HTTP policy model
  - The WireGuard plus shared-namespace design adds startup ordering and networking complexity without solving the separate IDE control plane that the repo itself documents
  - The packaged workflow is devcontainer- and Claude-shaped, not a neutral multi-agent control plane
- Open questions:
  - Could proxy-side secret substitution cover enough of `m20-host-credential-service` to make the helper path strictly secondary, or are there still important workflows that require local credential delivery?
  - Do we need transparent capture enough to justify the added WireGuard complexity, given the current explicit proxy plus firewall design already blocks direct egress?
  - Should any sandcat-inspired work land as devcontainer-only hardening rather than as part of the core backend contract?
- Verdict: `useful supporting reference`

### Sandcat implications for this project

- Worth bringing into the vision:
  - proxy-side secret substitution and leak detection as an optional credential mode
  - devcontainer hardening defaults: clear forwarded credential env vars, disable copied git config, disable local terminal, and remove forwarded sockets after VS Code attaches
  - read-only overlay of sandbox control files where the IDE workflow allows it
- Probably not worth bringing in as-is:
  - WireGuard transparent proxying as the default local path
  - Claude-specific host customization mounts
  - liberal "`allow GET *`" policy templates, which are directly at odds with prompt-injection resistance
- Research consequence:
  - Keep `sandcat` as a supporting reference for proxy-side secrets and devcontainer escape reduction, not as a candidate default backend

### jingkaihe/matchlock

- Item name: `jingkaihe/matchlock`
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: ephemeral microVMs with VM-level isolation, network allowlisting, MITM-based secret injection, and host-side policy controls
- Verified runtime boundary:
  - `documented`: Linux backend uses Firecracker
  - `documented`: macOS backend uses Virtualization.framework and supports Apple Silicon, not Intel
  - `documented`: host-side components include a policy engine, transparent proxy plus TLS MITM, VFS server, and JSON-RPC control surface
  - `documented`: host-guest communication uses vsock for exec, VFS, and readiness signaling
- Workspace model:
  - `documented`: `/workspace` is exposed through a guest FUSE mount backed by a host VFS server over vsock
  - `documented`: volume overlay mounts are isolated snapshots intended to disappear when the VM is torn down
  - `documented`: named disk volumes can persist across runs via `matchlock volume create` and `--disk @name:/mount`
- Persistence model:
  - `documented`: lifecycle and runtime metadata live in `~/.matchlock/state.db`
  - `documented`: image metadata lives in `~/.cache/matchlock/images/metadata.db`
  - `documented`: current runtime creates per-VM rootfs copies; an OCI layer-aware overlay-root redesign is proposed but not yet the baseline
- Network control model:
  - `documented`: Linux uses transparent interception with nftables DNAT on ports 80 and 443
  - `documented`: macOS defaults to Virtualization.framework NAT and switches to a gVisor userspace TCP/IP path when interception features are required
  - `documented`: interception is activated by allow-list rules, secrets, hook rules, or explicit `--network-intercept`
  - `documented`: the host-side interception plane supports allow-list enforcement, runtime allow-list mutation, and hook rules over host, method, and path
  - `documented`: hook rules can mutate requests and responses, including SSE `data:` lines, and can block traffic in `before` or `after` phases
  - `documented`: `--no-network` provides a fully offline mode
  - `documented`: empty allow-list means "allow all hosts" when interception is enabled
  - `documented`: non-HTTP protocols are not mutated by hook rules
- Runtime control model:
  - `documented`: the microVM is the primary isolation boundary
  - `documented`: guest exec adds defense in depth with PID and mount namespaces, selected capability drops, `no_new_privs`, and a seccomp filter that blocks ptrace and process-memory syscalls plus kexec
  - `documented`: a privileged mode exists and explicitly skips capability drops, seccomp, and `no_new_privs`
- Secrets model:
  - `documented`: real secrets never enter the VM; the sandbox sees placeholders and the host MITM path substitutes the real values
  - `documented`: secret replacement scope is request headers plus URL or query string
  - `documented`: request body replacement is intentionally not performed for secrets
- Observability model:
  - `documented`: lifecycle phases, cleanup state, runtime metadata, and resource identifiers are persisted in SQLite and exposed through `list`, `gc`, `rm`, and `prune` workflows
  - `documented`: leaked host resources can be reconciled after crashes with `matchlock gc`
  - `unknown`: public docs do not clearly describe a structured per-request audit log or exportable event stream comparable to a policy decision log
- Local platform support:
  - `documented`: Linux with KVM support
  - `documented`: macOS on Apple Silicon
  - `documented`: macOS Intel is not supported
  - `unknown`: no Windows path is documented
- Multi-agent compatibility:
  - `documented`: examples exist for Claude Code, Codex, MCP-style workloads, browser automation, and generic Go, Python, and TypeScript SDK usage
  - `documented`: JSON-RPC methods cover create, exec, file I/O, allow-list updates, port forwarding, cancellation, and close
- Primitive checklist:
  - Shared workspace mount: yes
  - Copy-on-write workspace: partial
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: partial
  - Home-directory shadowing: no explicit model
  - Scratch or temp volume isolation: yes
  - Domain allowlist proxy: yes
  - Path and method policy: yes
  - Transparent versus explicit proxying: transparent on Linux, mixed on macOS
  - DNS allowlist or DNS interception: unknown
  - Non-HTTP TCP policy: partial
  - SSH handling: unknown
  - Secret brokering: yes
  - Proxy-side secret substitution: yes
  - Output validation and quarantine: no
  - Audit logs: partial
  - Command hooks or deny rules: no
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: no
- Key strengths:
  - This is a genuine stronger-isolation reference, not just a container-plus-proxy variant
  - The split between host policy engine, host VFS service, and microVM runtime is directly relevant to `m22-backend-interface`
  - Network policy is materially richer than our current baseline: host allow-listing, path and method matching, request or response mutation, runtime allow-list edits, and offline mode
  - The VFS layer is more interesting than it first appears; it creates a host-side place to enforce or observe filesystem operations without bind-mounting the host repo directly into the guest
  - Lifecycle persistence and reconciliation are stronger than most research repos in this space
- Key limits:
  - Default network posture is weaker than our target model: interception is feature-triggered, and an empty allow-list in interception mode still means allow-all
  - Some of the most powerful controls are SDK-local callbacks and even `dangerous_hook` callbacks, which expand the trusted host-side execution surface and are a poor fit for a portable policy IR
  - The current image and rootfs model still relies on per-VM rootfs copies; the more compelling OCI layer-aware overlay-root design is still an ADR, not the shipped default
  - Cross-platform parity is real but not symmetrical: Linux gets Firecracker plus nftables transparency, while macOS falls back to Virtualization.framework NAT or gVisor-based interception
  - Privileged mode is useful, but it weakens in-guest defense in depth and should not be normalized as a default developer path
- Open questions:
  - Should our backend interface borrow Matchlock's split between host VFS and exec control planes, while explicitly refusing SDK-local callback policies as a first-class authoring model?
  - Is a FUSE-backed workspace better than a direct shared mount for our local Git-centric workflow, or does it introduce too much complexity and UX risk?
  - Could a stronger-isolation backend use Matchlock-like microVM and vsock primitives while still keeping our stricter default-deny policy semantics?
  - How much of Matchlock's lifecycle and GC model is worth copying into local agent-sandbox state management even for non-VM backends?
- Verdict: `likely core reference`

### Matchlock implications for this project

- Worth bringing into the vision:
  - a real microVM-backed stronger-isolation backend candidate
  - host-side VFS and exec control-plane separation as input to `m22-backend-interface`
  - richer HTTP policy concepts for `m14`, especially method and path matching plus response shaping
  - lifecycle persistence and explicit garbage-collection or reconcile workflows for leaked sandbox resources
- Probably not worth bringing in as-is:
  - feature-triggered interception with allow-all semantics when the allow-list is empty
  - SDK-local callback hooks and especially `dangerous_hook` as primary policy authoring primitives
  - assuming a FUSE or VFS workspace model is the right default for local developer ergonomics before measuring it against a shared mount model
- Research consequence:
  - Treat `matchlock` as a leading reference for the optional stronger-isolation backend and for backend-interface design, not as an argument to replace the current local default before we have comparative measurements
  - It should directly inform `m22-backend-interface` and `m24-runtime-spikes-vm`

### strongdm/leash

- Item name: `strongdm/leash`
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: Leash wraps AI agents in containers, monitors filesystem and network activity, and enforces Cedar-defined policy; on macOS it also offers an experimental native mode with a companion app
- Verified runtime boundary:
  - `documented`: Linux path is container-based and cgroup-scoped, not a microVM or alternate guest-kernel boundary
  - `documented`: Linux enforcement combines eBPF LSM hooks for file open, process exec, and socket connect with a local HTTP MITM proxy for hostname-aware policy and rewrite actions
  - `documented`: macOS native mode uses Endpoint Security plus Network Extension system extensions and does not launch the local MITM proxy
- Workspace model:
  - `documented`: the current working directory is bind-mounted into the target container
  - `documented`: extra bind mounts can be configured globally or per project in `~/.config/leash/config.toml`
  - `documented`: agent config directories such as `~/.claude` and `~/.codex` are optional prompt-driven mounts, remembered globally or per project
- Persistence model:
  - `documented`: persisted user config lives in `~/.config/leash/config.toml`
  - `documented`: Cedar policy source is persisted as `/cfg/leash.cedar`, while generated IR stays in memory
  - `unknown`: public docs do not yet make long-term runtime event retention or export guarantees as explicit as the live Control UI
- Network control model:
  - `documented`: Linux uses cgroup-scoped `socket_connect` enforcement plus iptables redirection into a local MITM proxy
  - `documented`: Cedar supports host and optional host:port matching with leading-wildcard domains, plus `HttpRewrite` header injection for approved hosts
  - `documented`: MCP traffic is observed in the proxy and specific MCP server or tool denies can be enforced there
  - `documented`: IPv6 and CIDR resources are not supported in v1 policies
  - `documented`: macOS native mode has no local MITM proxy, so HTTP header injection or rewrite is unavailable there
- Runtime control model:
  - `documented`: eBPF LSM hooks enforce or log file open, process exec, and network connect operations for selected cgroups
  - `documented`: policies hot-reload through BPF map updates without restarting the target process
  - `documented`: Record, Shadow, and Enforce modes can be switched live
  - `inferred`: the privileged Leash manager is part of the trusted computing base; this is not an unprivileged sandbox story
- Secrets model:
  - `documented`: Linux proxy can inject secrets at the HTTP layer, with the CA private key stored in a manager-only mount
  - `documented`: common API keys can also be forwarded directly as environment variables
  - `documented`: agent config directories can be mounted from the host into the container after an interactive approval flow
- Observability model:
  - `documented`: eBPF programs emit structured events through ring buffers, which feed the Control UI over WebSocket
  - `documented`: the Control UI supports live policy editing and validation, including Cedar autocomplete
  - `documented`: MCP server and tool metadata are surfaced in observed events on Linux
  - `unknown`: public docs do not clearly describe a stable external audit-log export or SIEM-friendly event sink
- Local platform support:
  - `documented`: Linux, macOS, and WSL are supported
  - `documented`: native macOS mode requires macOS 14+, admin approval, system extensions, and is still marked experimental
- Multi-agent compatibility:
  - `documented`: default images ship `claude`, `codex`, `gemini`, `qwen`, and `opencode`
  - `documented`: the MCP observer broadens the policy surface beyond just wrapping a single CLI
- Primitive checklist:
  - Shared workspace mount: yes
  - Copy-on-write workspace: no
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: partial
  - Home-directory shadowing: no
  - Scratch or temp volume isolation: no explicit model
  - Domain allowlist proxy: yes
  - Path and method policy: no documented general allow or deny model
  - Transparent versus explicit proxying: transparent on Linux, none on macOS native mode
  - DNS allowlist or DNS interception: unknown
  - Non-HTTP TCP policy: partial
  - SSH handling: unknown
  - Secret brokering: yes
  - Proxy-side secret substitution: partial
  - Output validation and quarantine: no
  - Audit logs: partial
  - Command hooks or deny rules: no
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: no
- Key strengths:
  - This is one of the clearest open references for combining kernel enforcement, L7 proxy control, and a human-editable policy language in one agent sandbox
  - The Record, Shadow, and Enforce workflow is a strong model for policy rollout and operator trust-building
  - Cedar as the persisted authoring format, with linting and in-memory transpilation to runtime-specific controls, is directly relevant to the policy-IR question in this repo
  - MCP is treated as a first-class policy surface rather than an afterthought
- Key limits:
  - Linux isolation is still container and cgroup based, not VM backed
  - Policy coverage is asymmetric across platforms; macOS native mode loses proxy rewrite features and MCP logging
  - The documented network policy model is host oriented, not a full path and method allow or deny system for general outbound HTTP
  - The secrets story is mixed: proxy-side injection exists, but direct env-var forwarding and host config mounts also intentionally place credentials close to the agent
- Open questions:
  - Should this project adopt Cedar or only borrow Leash's idea of one authoring language compiled to backend-specific enforcement?
  - Is eBPF LSM worth evaluating as its own Linux backend candidate, or only as an implementation technique inside a hardened container backend?
  - How much of Leash's Control UI and live policy workflow should influence the event schema and approval UX here?
  - What is the minimum acceptable capability degradation between Linux and macOS if the product exposes one nominal policy surface across both?
- Verdict: `likely core reference`

### Leash implications for this project

- Worth bringing into the vision:
  - Record, Shadow, and Enforce modes with live policy updates and visible event streams
  - a clear split between kernel or runtime enforcement, proxy-based L7 enforcement, and policy authoring
  - treating MCP calls as a first-class event and policy surface
  - an explicit compile step from a human-authored policy language into backend-specific controls
- Probably not worth bringing in as-is:
  - eBPF LSM as the only serious Linux answer, because it is powerful but not portable to macOS or VM-backed backends
  - optional host credential mounts and direct env-var forwarding as a primary secrets strategy
  - accepting materially different network semantics on macOS and Linux under one policy name without very clear degradation rules
- Research consequence:
  - Treat `leash` as a leading reference for policy IR, rollout modes, and observability, not as proof that a container boundary alone is sufficient for the project's stronger-isolation backend
  - It should inform `m21-capability-model` and `m22-backend-interface`, especially around event schema, policy compilation, and backend capability degradation

### Docker Sandboxes (`sbx`)

- Item name: Docker Sandboxes, `sbx`
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: one microVM per sandbox with its own kernel and a private Docker daemon; Docker states the hypervisor boundary is the isolation control
- Verified runtime boundary:
  - `documented`: KVM on Linux and the Windows Hypervisor Platform on Windows; the macOS hypervisor is not named and Virtualization.framework is `inferred`
  - `documented`: the agent runs as a non-root user with sudo inside the VM; the daemon is closed source
- Workspace model:
  - `documented`: virtiofs passthrough at the same absolute path with a host-side read cache, or `--clone` mounting the repo read-only and working on an in-VM clone
  - `documented`: hard-link escape from direct mounts is acknowledged
- Persistence model:
  - `documented`: sandboxes persist across restarts; per-sandbox and org policies persist host-side
  - `unknown`: snapshot or checkpoint semantics
- Network control model:
  - `documented`: all outbound TCP goes to a host-side proxy: TLS-terminating forward proxy for HTTP and HTTPS, transparent proxy for other TCP; UDP and ICMP are always blocked; an internal DNS resolver enforces policy
  - `documented`: rules are `connect:tcp` on hostnames with `*` and `**` wildcards, CIDRs, and ports; presets are Open, Balanced, and Locked Down; `--deny-network` per sandbox; organization governance overrides local allows
  - `documented`: no HTTP method or path rules; Docker states that domain fronting and user content on allowed domains are limits
- Runtime control model:
  - `documented`: filesystem policies for host paths and Cedar-based MCP policies enforced at a host-side MCP gateway
  - `unknown`: in-guest seccomp or capability reductions
- Secrets model:
  - `documented`: credentials injected as headers by the host proxy with sentinel values inside the VM; OAuth flows host-side; secrets in the OS keychain
- Observability model:
  - `documented`: `sbx policy log` with a per-request proxy mode column of `forward`, `forward-bypass`, or `transparent`
  - `unknown`: exportable structured audit stream
- Local platform support:
  - `documented`: macOS 14+ on Apple Silicon only, Windows 11 x64 with WHP, Linux with KVM on Ubuntu 24.04+ on x86_64 and arm64
- Multi-agent compatibility:
  - `documented`: Claude Code, Codex, Copilot, Cursor, Droid, Gemini, Kiro, OpenCode, and a plain shell
- Primitive checklist:
  - Shared workspace mount: yes
  - Copy-on-write workspace: partial, through `--clone`
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: yes in clone mode
  - Home-directory shadowing: unknown
  - Scratch or temp volume isolation: yes, VM-local
  - Domain allowlist proxy: yes
  - Path and method policy: no
  - Transparent versus explicit proxying: both
  - DNS allowlist or DNS interception: yes, internal resolver enforces policy
  - Non-HTTP TCP policy: yes, host and port
  - SSH handling: denied by default
  - Secret brokering: yes
  - Proxy-side secret substitution: yes
  - Output validation and quarantine: no
  - Audit logs: yes
  - Command hooks or deny rules: no
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: partial, through experimental SSH targets
- Key strengths:
  - The most complete local microVM product for agents on all three desktop platforms, with a private daemon per sandbox and workspace path preservation
  - Deny-by-default proxy plus credential injection with sentinel values matches this repo's model
  - Honest documentation of its own limits
- Key limits:
  - Closed source and Apple Silicon only on macOS
  - Host-level policy only; no method or path rules and no TLS-inspecting L7 rules
  - No user-owned compose or policy layering
- Open questions:
  - Should this repo target `sbx` as an external `microvm` backend rather than building one?
  - How does its virtiofs cache behave with large Git workspaces compared with Colima's mounts?
- Verdict: `likely core reference`

### Docker Sandboxes implications for this project

- Worth bringing into the vision:
  - a per-sandbox private daemon for agents that need Docker
  - a policy-decision log that names the proxy path taken per request
  - the explicit disclosure of allowlist limits in user docs
- Probably not worth bringing in as-is:
  - host-only policy without method or path rules
  - closed-source daemon dependence for the default backend
- Research consequence:
  - Treat `sbx` as the benchmark for the stronger-isolation backend and as a possible external backend rather than a design to copy

### coder/boundary

- Item name: `coder/boundary`
- Category:
  - proxy or policy layer
  - runtime substrate on Linux
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: process-level network jail with default-deny HTTP and HTTPS egress and audit logging
- Verified runtime boundary:
  - `documented`: `nsjail` backend uses a network namespace, veth, iptables redirect, and a dummy DNS server; it needs `CAP_NET_ADMIN` via `sudo` or `setpriv` re-exec
  - `documented`: `landjail` backend uses Landlock network restrictions plus `HTTP_PROXY` and `HTTPS_PROXY` environment variables, with no escalation
  - `unknown`: filesystem isolation under either backend
- Workspace model:
  - `inferred`: runs on the host filesystem as-is
- Persistence model:
  - not applicable; wraps one command
- Network control model:
  - `documented`: rules of the form `method`, `domain`, and `path` with `*` wildcards and segment-based path matching; `domain=github.com` does not match subdomains; YAML config supported
  - `documented`: transparent MITM under `nsjail` with a local CA injected through environment variables for curl, git, Python, and Node; explicit CONNECT under `landjail`
  - `documented`: the dummy DNS server prevents DNS exfiltration under `nsjail`
- Runtime control model:
  - `unknown`: no seccomp or capability reductions documented beyond the network namespace
- Secrets model:
  - `documented`: none; the proxy injects only a session-correlation header
- Observability model:
  - `documented`: audit logs, forwarded to Coder workspaces in the Coder integration
- Local platform support:
  - `documented`: Linux only; macOS and Windows are not supported
- Multi-agent compatibility:
  - `documented`: agent-agnostic wrapper; a Coder module integrates Claude Code
- Primitive checklist:
  - Shared workspace mount: not applicable
  - Copy-on-write workspace: no
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: no
  - Home-directory shadowing: no
  - Scratch or temp volume isolation: no
  - Domain allowlist proxy: yes
  - Path and method policy: yes
  - Transparent versus explicit proxying: transparent under `nsjail`, explicit under `landjail`
  - DNS allowlist or DNS interception: interception with a dummy answer
  - Non-HTTP TCP policy: unknown
  - SSH handling: unknown
  - Secret brokering: no
  - Proxy-side secret substitution: no
  - Output validation and quarantine: no
  - Audit logs: yes
  - Command hooks or deny rules: no
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: partial, through Coder
- Key strengths:
  - The closest single-binary analog of this repo's method, domain, and path rule model
  - The DNS sinkhole is a concrete answer to DNS exfiltration
- Key limits:
  - Linux only, with a privileged setup step for the strong backend
  - No secrets model and no filesystem boundary
- Open questions:
  - Is its rule grammar a good target or source for this repo's policy schema?
  - Does the `landjail` fallback leak through tools that ignore proxy environment variables?
- Verdict: `likely core reference`

### NVIDIA/OpenShell

- Item name: `NVIDIA/OpenShell`
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: sandboxes on Docker or Podman with optional microVM or Kubernetes compute drivers, a policy engine, a gateway, and a privacy router
- Verified runtime boundary:
  - `documented`: container by default; a YAML `filesystem_policy`, a best-effort Landlock block, and a process policy that blocks privilege escalation and dangerous syscalls; seccomp is `inferred`
  - `unknown`: which microVM technology the compute driver uses
- Workspace model:
  - `documented`: `include_workdir: true` in policy; mount mechanism `unknown`
- Persistence model:
  - `unknown`
- Network control model:
  - `documented`: minimal outbound by default; `network_policies` entries with endpoints of host, port, protocol, enforcement mode, and `read-only` access presets, plus a per-binary scope; hot-reload through `openshell policy set`; enforced by an L7 proxy returning 403
  - `unknown`: transparent versus explicit proxying and TLS termination
- Runtime control model:
  - `documented`: Landlock plus process restrictions inside the container
- Secrets model:
  - `documented`: providers are injected as environment variables at runtime and never written to the sandbox filesystem; the inference path strips caller credentials and injects backend credentials at the proxy
- Observability model:
  - `unknown`: audit-log format
- Local platform support:
  - `documented`: Linux, macOS on Apple Silicon, Windows through WSL2 experimentally
- Multi-agent compatibility:
  - `documented`: Claude Code, OpenCode, Codex, and Copilot CLI in the base image; Gemini, Pi, and Ollama through a community catalog; OpenClaw and Hermes through NemoClaw
- Primitive checklist:
  - Shared workspace mount: yes
  - Copy-on-write workspace: unknown
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: unknown
  - Home-directory shadowing: unknown
  - Scratch or temp volume isolation: unknown
  - Domain allowlist proxy: yes
  - Path and method policy: method presets, path unknown
  - Transparent versus explicit proxying: unknown
  - DNS allowlist or DNS interception: unknown
  - Non-HTTP TCP policy: partial, host and port
  - SSH handling: unknown
  - Secret brokering: yes
  - Proxy-side secret substitution: partial, inference path only
  - Output validation and quarantine: no
  - Audit logs: unknown
  - Command hooks or deny rules: partial, per-binary network scope
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: yes
- Key strengths:
  - The same shape as this repo: container plus L7 policy proxy plus per-agent images
  - Per-binary network scoping is a primitive this repo lacks
  - Broad agent catalog
- Key limits:
  - Alpha, heavier, and oriented toward a gateway and Kubernetes deployment
  - Proxy transparency, TLS handling, and audit format are undocumented in the reachable sources
- Open questions:
  - Is the policy schema a candidate compile target or a competitor format?
  - What does the microVM compute driver actually use?
- Verdict: `likely core reference`

### nolabs-ai/nono

- Item name: `nolabs-ai/nono`
- Category:
  - runtime substrate
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: kernel-native least-privilege sandboxing with no daemon, container, or VM
- Verified runtime boundary:
  - `documented`: Landlock on Linux and Seatbelt on macOS; per-tool child sandboxes through a broker
  - `unknown`: seccomp
- Workspace model:
  - `documented`: host filesystem with `fs_read` and `fs_write` grants
- Persistence model:
  - not applicable
- Network control model:
  - `documented`: per-profile allowlists and `network.deny_domain`; a credential proxy where each credential carries an `endpoint_policy` with a default of deny and allow entries of method plus path
  - `unknown`: TLS termination and DNS handling
- Runtime control model:
  - `documented`: signed profiles from a registry; `invocation_policy` argv prefixes per tool
- Secrets model:
  - `documented`: keyring-backed credentials injected by the proxy; the agent holds placeholder "phantom" tokens redeemed by the proxy
- Observability model:
  - `unknown`
- Local platform support:
  - `documented`: macOS, Linux, and WSL2; distro packages, Nix, and Homebrew
- Multi-agent compatibility:
  - `documented`: profiles for Claude Code, Codex, Pi, Copilot, Hermes, OpenCode, and OpenClaw
- Primitive checklist:
  - Shared workspace mount: host filesystem with grants
  - Copy-on-write workspace: no
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: yes through grants
  - Home-directory shadowing: no
  - Scratch or temp volume isolation: no
  - Domain allowlist proxy: yes
  - Path and method policy: yes, per credential
  - Transparent versus explicit proxying: explicit
  - DNS allowlist or DNS interception: unknown
  - Non-HTTP TCP policy: partial, Landlock ports
  - SSH handling: unknown
  - Secret brokering: yes
  - Proxy-side secret substitution: yes
  - Output validation and quarantine: no
  - Audit logs: unknown
  - Command hooks or deny rules: yes, argv prefixes
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: no
- Key strengths:
  - Per-credential endpoint policy is the most policy-IR-like credential model found
  - Placeholder redemption plus per-tool sandboxes keeps real secrets out of the agent process
  - Fast-moving with a dated changelog through September 2026
- Key limits:
  - OS-native boundary only, so weaker isolation than a container or VM
  - Cross-platform parity depends on Landlock versus Seatbelt feature gaps
- Open questions:
  - Could its profile registry format inform per-agent policy scaffolds here?
  - Does it fence DNS?
- Verdict: `likely core reference` for policy and credentials, `useful supporting reference` as a runtime

### stacklok/brood-box

- Item name: `stacklok/brood-box`
- Category:
  - runtime substrate
  - control plane
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: libkrun microVMs on Linux KVM or Apple Silicon Hypervisor.framework with a custom Go init
- Verified runtime boundary:
  - `documented`: microVM per session; the VM is stopped before workspace review and flush
  - `unknown`: VMM process confinement
- Workspace model:
  - `documented`: copy-on-write snapshot of the workspace through reflink or `clonefile`, mounted with virtio-fs; an interactive per-file diff review before a hash-verified flush back with setuid stripping and non-negotiable exclusions for `.env`, key files, `.ssh`, and `.aws`
- Persistence model:
  - `unknown` beyond the snapshot flush
- Network control model:
  - `documented`: DNS-aware egress firewall with `permissive` (default), `standard`, and `locked` profiles and `--allow-host host:port` for hostnames; per-workspace config cannot widen egress
  - `documented` by absence: no method or path rules
- Runtime control model:
  - `documented`: custom init with an embedded SSH server; MCP proxying from ToolHive
- Secrets model:
  - `documented`: env forwarding by name or glob, plus git token and SSH agent forwarding; no proxy-side substitution
- Observability model:
  - `unknown`
- Local platform support:
  - `documented`: Linux KVM and macOS on Apple Silicon
- Multi-agent compatibility:
  - `documented`: Claude Code, Codex, OpenCode, Hermes, and Gemini CLI plus custom images
- Primitive checklist:
  - Shared workspace mount: no, snapshot
  - Copy-on-write workspace: yes
  - Patch-only or branch-only writeback: partial, reviewed flush
  - Read-only parent or host mounts: yes
  - Home-directory shadowing: yes, VM-local
  - Scratch or temp volume isolation: yes
  - Domain allowlist proxy: DNS-aware firewall
  - Path and method policy: no
  - Transparent versus explicit proxying: none, firewall
  - DNS allowlist or DNS interception: yes
  - Non-HTTP TCP policy: yes, host and port
  - SSH handling: agent forwarding
  - Secret brokering: no
  - Proxy-side secret substitution: no
  - Output validation and quarantine: yes, diff review and setuid stripping
  - Audit logs: unknown
  - Command hooks or deny rules: no
  - Multi-agent abstraction: yes
  - Remote execution or gateway fleet support: no
- Key strengths:
  - The closest agent-agnostic local CLI in spirit to this repo, with per-agent images and egress profiles
  - Its reviewed writeback is a working implementation of this doc's high-assurance writeback idea
- Key limits:
  - Default egress profile is permissive
  - No L7 proxy and no secret substitution, so forwarded tokens live inside the VM
  - Experimental, and libkrun's shared security context needs VMM confinement
- Open questions:
  - Is the reviewed flush acceptable UX for interactive sessions, or only for headless tasks?
  - Could its workspace model be paired with this repo's proxy?
- Verdict: `likely core reference`

### TencentCloud/CubeSandbox

- Item name: `TencentCloud/CubeSandbox`
- Category:
  - runtime substrate
  - control plane
  - proxy or policy layer
- Research priority: `P0`
- Claimed runtime boundary:
  - `documented`: a dedicated OS kernel in its own KVM microVM per sandbox
- Verified runtime boundary:
  - `documented`: KVM microVMs managed by a hypervisor component with a containerd shim; Linux x86_64 and ARM64 only
  - `unknown`: which VMM is used and how the VMM process is confined
- Workspace model:
  - `unknown`
- Persistence model:
  - `documented`: cross-node pause and resume in 0.7.0
  - `unknown`: snapshot and volume semantics
- Network control model:
  - `documented`: an eBPF virtual switch enforces L3 and L4 policy; CubeEgress is a per-host transparent proxy reached through eBPF marking and iptables TPROXY, terminating TLS with an embedded CA
  - `documented`: rules match `scheme`, `port`, `sni` with wildcards, `host`, `method`, and exact or prefix `path`; present fields are ANDed and absent fields wildcard
  - `documented`: internal cluster traffic bypasses the proxy; unmatched custom-port TCP and UDP falls back to L3 and L4 policy
- Runtime control model:
  - `unknown`: in-guest hardening
- Secrets model:
  - `documented`: `Inject` objects add a header built from a `format` string with a `${SECRET}` placeholder and an operator-side `secret`; secrets never reach the sandbox
- Observability model:
  - `documented`: a JSONL access log with request records at a `metadata` level including TLS details, latency, and status, plus `security_event` records for denials and injections and `tls_handshake` records for handshake failures, with secrets redacted
- Local platform support:
  - `documented`: Linux with KVM only; cloud VMs, bare metal, or Kubernetes in preview
- Multi-agent compatibility:
  - `unknown`: no agent-specific packaging documented in the sources read
- Primitive checklist:
  - Shared workspace mount: unknown
  - Copy-on-write workspace: unknown
  - Patch-only or branch-only writeback: no
  - Read-only parent or host mounts: unknown
  - Home-directory shadowing: unknown
  - Scratch or temp volume isolation: yes, VM-local
  - Domain allowlist proxy: yes
  - Path and method policy: yes
  - Transparent versus explicit proxying: transparent
  - DNS allowlist or DNS interception: unknown
  - Non-HTTP TCP policy: yes, L3 and L4 through eBPF
  - SSH handling: unknown
  - Secret brokering: yes
  - Proxy-side secret substitution: yes, header injection
  - Output validation and quarantine: no
  - Audit logs: yes
  - Command hooks or deny rules: no
  - Multi-agent abstraction: no
  - Remote execution or gateway fleet support: yes
- Key strengths:
  - The closest open-source match to this repo's L7 rule model, with SNI and Host matching, method lists, and path prefixes, plus a documented audit schema
  - eBPF steering with TPROXY is a transparent design that does not depend on proxy environment variables
- Key limits:
  - Linux and cluster oriented; no local macOS story
  - No workspace model or in-guest hardening documented in the sources read
- Open questions:
  - Is the rule grammar close enough to this repo's schema to share test corpora?
  - Does the audit schema cover redirect chains and per-request policy decisions?
- Verdict: `likely core reference`

### Implications of the 2026 open-source comparables

- Worth bringing into the vision:
  - a DNS sinkhole option beneath the proxy, from Boundary, httpjail, airut, and iron-proxy
  - per-credential endpoint policy and placeholder redemption, from nono and Claude Code
  - a reviewed, hash-verified writeback mode, from brood-box
  - per-binary network scoping, from OpenShell
  - policy loaded from the repository default branch so the agent cannot edit it, from airut
  - eBPF steering with TPROXY and a JSONL audit schema with security-event records, from CubeSandbox
- Probably not worth bringing in as-is:
  - OS-native-only boundaries as the default backend
  - permissive default egress profiles
  - libkrun without documented VMM confinement
- Research consequence:
  - OpenShell and brood-box join Matchlock and Leash as the core open-source references; Boundary, nono, airut, and iron-proxy are the references for the proxy and credential layer

## Research backlog: commercial products

These are worth a separate commercial landscape pass. The goal is not just feature comparison. It is to identify the actual substrate each product uses and where its control planes live.

For each commercial product, capture:

- Runtime boundary: container, gVisor, microVM, full VM, isolate, or Kubernetes primitive
- Workspace model: bind mount, sync, persistent disk, snapshot, object storage, or virtual filesystem
- Network model: unrestricted, deny-all, domain policy, CIDR policy, proxy transforms, or VPC integration
- Runtime controls: syscall mediation, VM boundary, container hardening, guardrails, audit logs
- Persistence model: snapshot, suspend-resume, volumes, or external object store
- Hosting model: vendor cloud, self-hosted, BYOC, or hybrid

Evidence note for the September 2026 pass: vendor pages outside GitHub and the Anthropic docs hosts could not be fetched from inside this sandbox. Claims marked `search extract` come from search-engine extracts of the vendor's own page and should be re-read from the primary page before they drive a decision.

### Where the hosted landscape moved between March and September 2026

- Deny-by-default egress plus a host allowlist plus proxy-side credential injection is now the baseline expectation across hosted sandboxes; it is no longer a differentiator
- The differentiators moved up the stack:
  - HTTP method, path, query, and header matchers on top of host rules (Vercel, Codex cloud)
  - request forwarding to a user-controlled upstream with a signed identity header (Vercel)
  - TLS interception with a per-instance ephemeral CA whose key never enters the sandbox (Cloudflare)
  - live policy edits on a running sandbox without restart (Cloudflare, Modal, E2B, Vercel, Daytona); Koyeb notably redeploys and loses in-memory state
- Vendors now document their own allowlist holes: bypass channels such as the vendor API host, MCP connectors, and git proxies (Anthropic), DNS exfiltration (AWS AgentCore sandbox mode), and domain fronting or user-generated content on allowed domains (Docker)
- Semantic service rules are appearing for git: branch-scoped push and a pinned GraphQL operation set in Anthropic's GitHub proxy go beyond host allowlisting
- Placeholder secrets substituted per host at the network layer (Deno, Docker Sandboxes, Cloudflare) are converging on the same shape this repo uses for proxy-side injection
- Continuous checkpoint and restore is now standard in VM-backed hosted products (Fly Sprites, Vercel snapshots, GKE Pod Snapshots); a Docker-based local tool cannot match that and should say so
- Consolidation: OpenAI announced an agreement to acquire Ona (June 2026, `search extract`), Koyeb announced it is joining Mistral AI (February 2026, `search extract`), and Daytona moved core development to a private codebase (June 2026, `documented` in the public repo README)

### Ona

- Public docs describe a two-plane architecture: Ona-hosted management plane plus runners that execute environments and agents in Ona Cloud or in your own AWS or GCP account
- Ona docs state persistent storage is attached to the underlying VM
- Dev Containers can run inside that environment, and the Dev Container network is isolated from the VM by default
- Guardrails, audit logs, and command deny lists are part of the product surface
- Inference: likely VM-backed developer environments with Dev Container support layered on top
- Open question: the exact current runtime substrate is not stated clearly in the public docs; the company also publicly documented leaving Kubernetes, so the current runner implementation needs deeper review
- Update, September 2026:
  - `search extract`: OpenAI announced an agreement to acquire Ona in June 2026, with the team joining the Codex group; this was not independently verified from inside the sandbox
  - `documented`: the `gitpod-io/gitpod` README now says Gitpod has been renamed to Ona and no longer recommends Gitpod Classic
  - Implication: treat Ona as a likely Codex-adjacent execution and BYOC layer rather than a neutral platform; its run-in-your-VPC runner model and ten-minute auto-checkpoint cadence are still the ideas worth tracking

### CodeSandbox SDK, now marketed as Together Code Sandbox

- Official blog says sandboxes run inside microVMs
- Official blog also says the system is built on Firecracker, with custom snapshot and live-clone work
- Key primitives include memory checkpointing, clone-from-snapshot, persistent filesystem with built-in git versioning, and Docker or Docker Compose customization through Dev Containers
- Update, September 2026:
  - `search extract`: Together AI acquired CodeSandbox in December 2024 and now markets the product as Together Code Sandbox; the npm package remains `@codesandbox/sdk`
  - `search extract`: snapshot resume in roughly half a second and git-versioned persistent storage remain the headline claims
  - No new network-policy features surfaced in this pass
- Fit: direct microVM backend with mature snapshotting and developer-environment features

### Runloop

- Docs say Devboxes are isolated, ephemeral virtual machines
- The product site says the infrastructure uses a custom bare-metal hypervisor and describes two layers of security, VM plus container
- Docs describe snapshots, suspend-resume, blueprints, account secrets, object mounts, tunnels, and network policies
- Network policies appear hostname-oriented in the product blog, while some docs also mention SSH access through a transparent proxy
- Update, September 2026:
  - `search extract`: network policies are account-scoped allow and deny egress rules attached to a Devbox at launch
  - `unknown`: third-party coverage describes a credential gateway with opaque token injection; not found in primary docs during this pass
  - `search extract`: VPC deployment on AWS, GCP, and Azure, and Runloop is one of the sandbox providers in the OpenAI Agents SDK
  - `companion doc`: agent gateways and MCP brokering are reported as product features; not verified here
- Fit: VM-backed sandbox platform with additional containerization or image layering inside the VM

### exe.dev

- Docs describe exe.dev as a subscription service for quickly-created virtual machines with persistent disks
- Docs state exe.dev VMs run on rented bare metal and currently use Cloud Hypervisor, while warning that this is an implementation detail and may change
- Docs say new VMs start from a container image wired to a block device, making creation take about two seconds, with the tradeoff that users do not choose the kernel
- The product positions VMs as normal Linux computers that can run `apt`, `systemd`, agents, and Docker-oriented workflows
- Networking is exposed through exe.dev-managed HTTPS/TLS termination and proxying rather than giving each VM its own public IP; SSH is also brokered through the service
- Pricing docs describe many VMs sharing a user's CPU and RAM pool, with persistent disk charged or pooled separately
- Update, September 2026:
  - `search extract`: no architectural change; an HTTP API with self-minted bearer tokens was added, and a May 2026 host-loss incident was restored from hourly backups according to the status page
  - `search extract`: secrets are described as injected at the network edge
- Fit: hosted Cloud Hypervisor-backed persistent VM cloud with fast creation, copy-friendly VM semantics, and Docker-capable guest environments
- Difference from this project's local-runtime question: exe.dev makes the remote VM the primary computer, so it avoids the hardest local requirement here: low-latency synchronization with an existing host workspace

### GKE Agent Sandbox and the Google agent platform

- Google documents this as a Kubernetes controller and API for creating ephemeral runtime environments
- Runtime isolation is achieved with gVisor; Google also documents Kata as another option
- The system introduces Kubernetes-native resources such as `SandboxTemplate`, `SandboxWarmPool`, and router components
- On GKE, the docs position it alongside GKE Sandbox and pod-level checkpoint or restore features
- Update, September 2026:
  - `search extract`: GKE Pod Snapshots went GA in May 2026; gVisor checkpoints memory, CPU, and GPU state plus filesystem deltas to Cloud Storage, restore streams pages lazily, and an application signals readiness by writing to `/proc/gvisor/checkpoint`
  - `search extract`: Agent Sandbox restore is modeled as a new `SandboxClaim` against the same template, with the controller picking the latest snapshot
  - `documented`: upstream `kubernetes-sigs/agent-sandbox` is still `v1beta1`; network policy remains an exploration topic rather than a CRD feature; an AKS example using Kata on Azure Linux was added in August 2026
  - `search extract`: Vertex AI was renamed Gemini Enterprise Agent Platform in April 2026, with sandbox templates and sandbox snapshots in preview; the runtime for the managed code-execution service is not named, so it is `unknown` whether it is gVisor
- Fit: Kubernetes-native sandbox controller built on gVisor or Kata, not a standalone local runtime

### Modal Sandboxes

- Modal documents Sandboxes as secure containers for untrusted code
- Modal's security docs explicitly say Sandboxes are built on top of gVisor
- Network controls include `block_network=True` or CIDR allowlists
- Persistence uses filesystem, directory, and memory snapshots
- Update, September 2026:
  - `search extract`: a domain allowlist for TLS traffic is in beta, runtime policy updates are allowed but can only tighten, static egress IPs are available through `modal.Proxy`, and tunnels can carry an inbound CIDR allowlist
  - `search extract`: memory snapshots are retained for seven days and filesystem snapshots for thirty, with a 24 hour maximum sandbox lifetime
  - `companion doc`: experimental sidecar-based traffic inspection is reported; not verified here
- Fit: gVisor-backed secure container service with strong snapshot support; network policy is moving from CIDR-only toward domain rules

### Daytona Sandboxes

- Public docs describe isolated sandboxes managed by Daytona, with snapshots built from Docker or OCI images and a declarative image builder
- Sandboxes can run Docker-in-Docker and even a nested k3s cluster
- Docs expose firewall controls and network limits; public examples show block-all and allowlist behavior around network addresses
- Update, September 2026:
  - `documented`: the public `daytonaio/daytona` README states that as of June 2026 core development moved to a private codebase and the repository receives no further updates
  - `inferred`: the default runtime is Docker containers, with Sysbox referenced in security materials and Kata described as optional by third parties; this was not confirmed from a Daytona primary page
  - `search extract`: network controls are `networkBlockAll` plus an IPv4 CIDR allowlist, with hostnames, domains, and IPv6 documented as unsupported, an `outboundProxyUrl` to chain to your own proxy, and runtime updates on a running sandbox
  - `unknown`: a "Domain Firewall" marketing page contradicts the CIDR-only docs; unresolved
  - `companion doc`: the companion architecture doc reports enforced domain and CIDR rules, container and VM sandbox classes, upstream proxy support, and host-scoped secret substitution; the domain-rule claim conflicts with the search extract above, and neither page could be read directly here
- Fit: previously an open-source candidate for self-hosting; now a closed platform whose main relevance is its proxy-chaining option and its Docker-plus-Sysbox default boundary

### E2B

- Docs say each sandbox is a fast, secure Linux VM created on demand
- E2B's site says each sandbox is powered by Firecracker
- Templates are defined from Dockerfiles or base images and then converted into a microVM
- Update, September 2026:
  - `search extract`: network policy is `allowOut` and `denyOut` with domain and CIDR rules where allow wins, runtime updates through `updateNetwork`, create-time `allowPublicTraffic` and `maskRequestHost`, workload-identity token injection through a context callback, and per-host request transforms in public beta
  - `documented`: `e2b-dev/infra` is Apache-2.0, built on Terraform, Nomad, Consul, and Firecracker, with GCP fully supported and AWS in beta
  - `search extract`: enterprise BYOC into a customer AWS VPC; desktop SDKs moved into the monorepo
  - `companion doc`: internet access is enabled by default in the SDK, so `allowOut` and `denyOut` are opt-in restrictions
- Fit: Firecracker microVM platform with template building and optional BYOC or self-hosted modes; its request-transform and token-injection features are now close to this repo's proxy model

### Blaxel

- Docs describe sandboxes as lightweight virtual machines
- Infrastructure docs say Mark 3 uses microVMs for low cold starts
- The platform emphasizes standby-mode snapshots that preserve processes and filesystem state, with resume in under 25ms
- Update, September 2026:
  - `search extract`: the egress proxy injects headers, body fields, and secrets server-side; static egress gateways are in private preview; Blaxel is a provider in the OpenAI Agents SDK
- Fit: microVM platform with aggressive suspend-resume and snapshot lifecycle management

### AgentSandbox.co

- Public docs describe a secure code-execution API with sessions, artifacts, Python and shell execution, and automatic reproducible dependency installation
- Public docs are much thinner than other vendors' docs on the actual underlying runtime
- Inference: product appears to be a managed code-execution service rather than a full general-purpose development environment platform
- Open question: determine whether the runtime is container-based, VM-based, or delegated to another substrate
- Not re-verified in the September 2026 pass

### Sandbox0

- Product page explicitly says it is built on Kubernetes and Kata Containers
- It also says files are persisted to S3 in a POSIX-compatible way and that compute and storage are decoupled
- The product claims E2B API compatibility with a different internal architecture
- Fit: Kubernetes-native Kata backend with externalized filesystem persistence rather than long-lived VM disks
- `unknown`: not found under this name in the September 2026 pass; it may have been renamed

### Vercel Sandbox

- Vercel docs say each sandbox runs in a Firecracker microVM
- System docs say the base image is Amazon Linux 2023 with selectable runtimes and `sudo` available
- Firewall docs expose `allow-all`, `deny-all`, and user-defined network policies with domain and CIDR rules
- Vercel also documents credentials brokering by proxy-side header injection and TLS termination for transformed requests
- Update, September 2026:
  - `search extract`: persistence went GA in May 2026 with named sandboxes, `getOrCreate`, `fork`, lifecycle hooks, tags, and retained snapshots
  - `search extract`: firewall rules gained matchers scoped by path, method, query string, and headers, plus request forwarding through `forwardURL` to an allowed upstream with forwarded-host headers and a `vercel-sandbox-oidc-token` header so the upstream can authenticate the sandbox; policies can be updated live
  - `search extract`: brokering depends on SNI, and a catch-all rule with per-domain transforms passes SNI-less connections through unmodified
  - `search extract`: the HackerOne scope states the Firecracker microVM is the security boundary and in-guest namespaces are for developer experience
- Fit: hosted Firecracker microVM service with the richest documented L7 policy surface of the hosted products; its matcher model is the closest analog to this repo's method and path rules

### Cloudflare Sandbox SDK

- Cloudflare docs describe a three-layer architecture: Workers, Durable Objects, and Containers
- The sandbox runtime docs say code runs in an isolated Linux container with a full Linux filesystem
- The architecture docs also say the Containers layer provides VM-based isolation and full Linux capabilities
- Update, September 2026:
  - `search extract`: Sandboxes went GA in April 2026 with zero-trust credential injection, TLS interception through a per-instance ephemeral CA whose private key stays in a runtime sidecar, `allowedHosts` and `deniedHosts` globs where an allowlist implies deny-by-default, and dynamic outbound handlers that change policy without restart
  - `documented`: Cloudflare's Managed Agents integration notes say "both microVM and isolate based sandboxes have an outbound Worker proxy injected", which implies container sandboxes are microVM-backed; the boundary is still not spelled out
  - `search extract`: Dynamic Workers (V8 isolates) are in open beta with `globalOutbound: null` to block egress entirely
- Fit: Cloudflare-managed sandbox service that exposes durable identities and orchestration through Workers and Durable Objects; the per-instance CA design is directly relevant to how this repo distributes its mitmproxy CA

### Fly.io Sprites

- `search extract`: Sprites are full Linux VMs on Firecracker and KVM with no container image required, 100 GB of persistent NVMe per sprite, and automatic checkpoints while working, with the last five checkpoints mounted read-only under `/.sprite/checkpoints`
- `search extract`: restore is roughly 300 ms from warm and one to twelve seconds from cold; idle sprites cost storage only; an MCP endpoint lets an agent provision sprites itself
- `unknown`: no primary description of an egress allowlist or credential proxy was found
- Fit: hosted Firecracker VM product; the "checkpoint continuously and mount prior checkpoints read-only" model is a cheap rollback primitive worth imitating for local per-agent state volumes

### Deno Sandbox

- `documented`: each sandbox is a Firecracker microVM, ephemeral, with disk wiped on destroy
- `documented`: all outbound traffic routes through a proxy, but the default is unrestricted; `allowNet` accepts hosts, `host:port`, wildcard domains, IPv4, and bracketed IPv6, with no method or path rules
- `documented`: secrets are declared per environment variable with a list of allowed hosts; the variable holds a placeholder and the real value is substituted at the network layer only for approved hosts
- `search extract`: volumes and snapshots exist; the service is in beta in US and EU regions and inherits Deno Deploy's SOC 2 and ISO 27001 posture
- Fit: hosted Firecracker microVM with the cleanest developer-facing secret shape in this list; its default-allow network posture is the opposite of this repo's target model

### AWS Bedrock AgentCore and Lambda MicroVMs

- `search extract`: AgentCore Runtime gives each session a dedicated microVM with a localhost platform server inside the isolation boundary, and memory is sanitized at teardown; Code Interpreter runs on Firecracker
- `search extract`: network modes are `PUBLIC` with no restrictions, `SANDBOX` which AWS clarified allows only S3 and DNS after researchers exfiltrated data through DNS and reached S3 and DynamoDB, and `VPC` where security groups, NACLs, flow logs, and Route 53 Resolver DNS Firewall provide the only domain-level control
- `search extract`: Lambda MicroVMs are a newer Firecracker-based option with snapshot start, up to eight hours of runtime, public internet by default, and a VPC egress connector to restrict traffic; they are listed as an Anthropic Managed Agents self-hosted backend
- `unknown`: AgentCore Browser network specifics were not verified
- Fit: hosted microVM platform without a native domain allowlist; the `SANDBOX` mode bypasses are a concrete reminder that a local sandbox must block direct DNS, not just direct TCP

### Azure Container Apps dynamic sessions and ACA Sandboxes

- `documented`: dynamic sessions use Hyper-V isolation, with egress disabled by default through `--network-status EgressDisabled`, and offer code-interpreter and custom-container pools with cooldown teardown
- `documented` in the docs, `search extract` for the microVM wording: ACA Sandboxes entered public preview in June 2026 as a first-class `Microsoft.App/SandboxGroups` resource with prewarmed pools, sub-second start, scale-to-zero, egress policies with domain-based allow and deny plus CIDR rules and VNet integration, and Blob or Data Disk persistent volumes
- `search extract`: Microsoft positions ACA Sandboxes as the successor to dynamic sessions and says the same fabric backs GitHub Copilot cloud sandboxes and Foundry hosted agents
- `documented`: the Foundry Agent Service code interpreter runs on dynamic sessions with no outbound network and a one hour session limit
- Fit: Hyper-V isolated hosted sandboxes with a domain-aware egress policy; relevant mainly as evidence that domain rules plus CIDR rules plus VNet is the hyperscaler policy shape

### Anthropic Managed Agents and Claude Code on the web

- `documented`: Managed Agents has been in public beta since April 2026 and self-hosted sandboxes since May 2026; Anthropic docs describe the cloud sandbox as an isolated Linux container on Ubuntu 24.04 x86_64
- `documented`: Claude Code on the web runs in an isolated, Anthropic-managed VM with a security proxy for HTTP and HTTPS and a DNS-level audit trail
- `inferred`: third-party research describes gVisor with seccomp disabled and root inside the Managed Agents sandbox; not stated in Anthropic docs
- `documented`: Managed Agents network policy is `unrestricted` (the API default, minus a safety blocklist) or `limited` with `allowed_hosts` supporting bare hosts and wildcard domains, plus `allow_package_managers` and `allow_mcp_servers` flags
- `documented`: Claude Code on the web offers network levels None, Trusted, Full, and Custom, and explicitly lists paths that bypass the allowlist: the GitHub proxy, MCP connectors, API-credential hosts, and `api.anthropic.com` even at level None
- `documented`: the GitHub proxy swaps a scoped in-VM credential for the real token and enforces push only to the current branch, repository scope, and a pinned GraphQL operation set; API credentials are injected as headers for listed hosts after the request leaves the VM and never for `api.anthropic.com` or public registries
- `documented`: for self-hosted environments Anthropic cannot enforce egress and instead prescribes default-deny at the operator's boundary, blocking `169.254.169.254` in the container network namespace, per-session minted git credentials, one container per session, and an optional Anthropic git proxy
- `documented`: supported self-hosted Managed Agents backends include Lambda MicroVMs, Blaxel, Cloudflare, Daytona, E2B, Fly.io, GKE Agent Sandbox, Modal, Namespace, Superserve, and Vercel
- Fit: vendor-hosted agent runtime, not a local backend; the semantic GitHub rules and the explicit allowlist-bypass disclosure are the two ideas to copy into this repo's policy model and docs

### OpenAI Codex cloud and Agents SDK sandboxes

- `search extract`: Codex cloud runs tasks in isolated OpenAI-managed containers; the VMM, if any, is `unknown`
- `search extract`: a two-phase model where the setup phase has network and secrets, then secrets are removed before the agent phase starts, and the agent phase is offline by default
- `search extract`: per-environment internet access is Off or On with domain allowlist presets (none, common dependencies, all) plus custom domains, and an allowed HTTP method list such as GET, HEAD, and OPTIONS only
- `search extract`: the OpenAI Agents SDK added a `Sandbox` abstraction in April 2026 with filesystem snapshots, package install, port forwarding, and resumable state across seven hosted providers: Blaxel, Cloudflare, Daytona, E2B, Modal, Runloop, and Vercel
- Fit: vendor-hosted runtime; method-level allowlisting and "secrets only during setup" are both cheap to express in this repo's policy model and worth adding as documented modes

### Northflank

- `search extract`: per-workload choice of Kata with Cloud Hypervisor, Firecracker, or gVisor; self-serve BYOC on AWS, GCP, Azure, Oracle, CoreWeave, Civo, and bare metal; SOC 2 Type 2
- `unknown`: no sandbox-specific egress-policy documentation was found
- Fit: hosted and BYOC multi-runtime platform; useful as a reference for offering gVisor, Kata, and Firecracker behind one workload API

### Koyeb Sandboxes

- `search extract`: Koyeb announced in February 2026 that it is joining Mistral AI and will keep investing in Sandboxes
- `inferred`: Cloud Hypervisor microVMs through Kata on bare metal; Koyeb itself says microVMs on bare metal
- `documented`: network policy is `block_network=True` or an `outbound_allowlist` of IPs and CIDRs only, and changing the policy redeploys the sandbox and loses in-memory state
- Fit: hosted microVM platform; mainly a cautionary example of policy changes that cannot be applied live

### Hopx

- `search extract`: Firecracker microVM per sandbox started from prebuilt snapshots in roughly 100 ms, root access, full state persistence, SDKs in six languages, an MCP server, and a BYOC claim
- `unknown`: network policy
- Fit: hosted microVM platform; low relevance beyond the snapshot-start pattern

### Kernel

- `documented`: open-source browser images run Chromium on Unikraft unikernels or in Docker, with standby snapshots restored in under 20 ms
- `search extract`: networking is a managed proxy pool for egress steering, not an allowlist
- Fit: low relevance unless this repo grows a browser profile; a concrete example of the unikernel path noted under Unikraft

### Superserve

- `documented`: Apache-2.0 repo describing Firecracker microVMs that can pause indefinitely, snapshot, fork, and resume
- `search extract`: a broker between the agent and third-party APIs plus URL and IP egress control with per-connection logging, per-second pricing, and a place on Anthropic's self-hosted Managed Agents backend list
- `unknown`: self-hosting components are not documented in the README
- Fit: hosted microVM platform; its broker-plus-egress-log combination is the same shape as this repo's proxy

### Buildkite Cleanroom

- `documented`: MIT, self-hosted; compiles a repo's `cleanroom.yaml` into warm microVM snapshots with dependencies and security controls baked in, on a VM layer Buildkite calls SporeVM
- `documented`: egress is deny-by-default by hostname and port and is re-applied on every resume and fork; a host-side gateway brokers credentials; OCI base images are pinned by digest
- Fit: self-hosted microVM sandbox with policy-as-code in the repo; its digest-pinned base images and per-repo policy file map directly onto this repo's `.agent-sandbox/` layout and `make bump` workflow

### Namespace

- `search extract`: microVMs with a dedicated kernel, job-wide network policies to constrain egress, and audit logging with SIEM export; the VMM is not named
- `search extract`: underlies Warp's Oz product and is an Anthropic self-hosted backend
- Fit: enterprise CI-style hosting; low relevance as a local backend

### Multi-provider client libraries: Cased sandboxes, Warp Oz

- `documented`: Cased `sandboxes` is an MIT Python library and CLI exposing one API over E2B, Modal, Daytona, Hopx, Vercel, Sprites, and experimental Cloudflare, with no cross-provider network-policy abstraction
- `search extract`: Warp Oz runs Docker-based sandboxes on Namespace with per-sandbox filesystem and network isolation plus a virtual display, and offers a self-hosted worker image; the self-hosted worker boundary is `inferred` to be plain Docker
- Fit: evidence that provider-neutral sandbox clients are appearing but still stop short of a common policy model

### Freestyle

- `unknown`: third-party references describe full Linux VMs with nested virtualization, volumes, snapshots, network policy, and secret protection; not verified in this pass

### Low-relevance mentions

- Replit: only generic VM or container descriptions surfaced; no first-party 2026 architecture doc; `unknown`
- StackBlitz WebContainers: browser-side Node.js on WebAssembly; no Linux, no arbitrary toolchains, egress governed by browser CORS rather than policy; useful only as a "nothing leaves the browser" contrast
- EU providers: no native agent-sandbox product found at Scaleway or OVHcloud; EU-sovereign options are self-hosting E2B infra, OpenSandbox, or Cleanroom, or BYOC on Northflank, plus EU-founded vendors Blaxel and Koyeb

## Research backlog: backend abstractions and runner contracts

These projects standardize how a harness talks to a sandbox. They matter for `m22-backend-interface` more than for the isolation question. All claims below were read from in-repo sources.

### OpenHands and the software-agent-sdk

- `documented`: the OpenHands main repository is now a control-center frontend, and the SDK, Agent Server, and workspaces live in `OpenHands/software-agent-sdk`; the legacy `Runtime` interface with Docker, local, remote, Kubernetes, and CLI implementations exists at tag 1.5.0, and the Modal, Daytona, E2B, and Runloop implementations were dropped before 0.50
- `documented`: the current `BaseWorkspace` is an action-agnostic handle with `execute_command`, file upload and download, git changes and diff, optional pause and resume, and a completion callback; `DockerWorkspace`, `ApptainerWorkspace`, `APIRemoteWorkspace`, and a cloud workspace exist; no Kubernetes workspace is exported
- `documented`: the Agent Server is a FastAPI and WebSocket service inside the sandbox with routers for bash, files, git, events, conversations, tools, MCP, VS Code, desktop, and hooks; its image installs Claude Code, Codex, and Gemini CLI as ACP providers
- `documented`: isolation is delegated entirely to the container or VM hosting the server; network policy is not in the contract; `forward_env` passes host variables into the container
- Fit: the strongest reference for an "agent server inside the sandbox, thin client outside" contract and event API; silent on policy compilation

### SWE-ReX

- `documented`: version 1.4.0; `AbstractDeployment` owns lifecycle and `AbstractRuntime` owns operations: bash sessions with `BashAction`, one-shot `execute`, file read and write, and upload; a FastAPI server inside the target makes local and remote runtimes interchangeable
- `documented`: backends are local, Docker, Modal, Fargate, remote, dummy, and a work-in-progress Daytona; no network policy, snapshot, port, or secrets concepts in the contract
- Fit: a clean lifecycle-versus-operations split and well-specified interactive-shell semantics; no policy surface to borrow

### Inspect sandbox environments

- `documented`: `inspect_ai` 0.3.263 dated 2026-09-03; the `SandboxEnvironment` interface defines `exec` with input, cwd, env, user, timeout, and concurrency, a streaming `exec_remote`, file read and write, and an optional `connection` with login command and port mapping; 100 MiB read and 10 MiB exec output limits; typed expected errors surfaced to the model and unexpected errors failing the sample; lifecycle class methods for task and sample init and cleanup
- `documented`: providers are built-in Docker and local plus external Kubernetes, Daytona, Modal, EC2, Proxmox, and Vagrant; Docker-compatible providers accept `Dockerfile` and `compose.yaml` as portable config
- `documented`: the generated Docker compose sets `network_mode: none`; the agent bridge runs an in-sandbox model proxy that keeps provider credentials host-side; the mitmproxy example states that the proxy provides interception, not the egress boundary
- `documented`: the Kubernetes provider defaults to the gVisor runtime class, no internet, Cilium-enforced `allowDomains` limited to ports 80 and 443 with SNI enforcement, a per-pod CoreDNS sidecar, and documented domain-fronting mitigations; its docs recommend against internet access at all
- Fit: the best-specified provider contract found, with an error taxonomy and output limits worth copying; network policy stays per-provider config

### Harbor

- `documented`: version 0.22.0 with dated changelog entries through 2026-08-22; environments for Docker, Podman, Apple `container`, Kata, Singularity, Daytona, E2B, Modal, Runloop, GKE, OpenShift, Blaxel, OpenSandbox, Vercel, and many more, lazily imported
- `documented`: `BaseEnvironment` exposes start, stop, exec, upload, and download plus a `capabilities` declaration covering GPUs, internet disable, network allowlist, per-entry-type flags for hostnames, wildcards, IP literals, and CIDRs, dynamic network policy, mounts, and compose support
- `documented`: `NetworkPolicy` has `network_mode` of public, no-network, or allowlist plus `allowed_hosts` of hostnames, wildcards, IPs, or CIDRs, never URLs or ports; policies are phase-scoped to environment, agent, and verifier; a run fails at init when a provider lacks a requested capability, and policies can switch mid-trial where supported
- `documented`: Docker enforcement is an nftables sidecar sharing the task network namespace and needs a kernel feature Docker Desktop may lack; the Kata environment cannot join the sidecar and so does not support network policy; E2B, Vercel, and TensorLake each enforce differently
- Fit: the closest published analog to a normalized policy plus per-backend capability declaration with fail-closed validation; its choice to let each provider compile the policy is the main design fork to weigh against a central compiler

### METR Vivaria and the Task Standard

- `documented`: METR is moving internal tooling to Inspect and ramping down Vivaria; the model is task environments with an `iptables` or `docker-network` no-internet mode, full-internet networks gated per model with LLM-based action checking, and a task-level `full_internet` permission
- Fit: precedent for two policy tiers, no internet versus full internet with monitoring; the codebase itself is winding down

### OpenSandbox protocol

- `documented`: a lifecycle API with create, get, delete, snapshots, pause and resume, expiration renewal, and per-port endpoints; the create request carries an image or snapshot, resource limits, volumes, `networkPolicy` with `defaultAction` and egress rules, a credential proxy flag, and pool references; an in-sandbox `execd` API for commands, bash sessions, code contexts, files, PTY over WebSocket, and isolated sessions with diff and commit; an egress sidecar API for policy and the Credential Vault
- `documented`: the egress sidecar combines a DNS proxy with optional nftables IP sets bound to TTLs, blocks DNS over HTTPS, and can run a transparent mitmproxy for the Credential Vault; the secure-runtime option is server-level configuration
- Fit: the only public OpenAPI-style sandbox protocol; its `networkPolicy` and egress sidecar are the closest to this repo's proxy-plus-firewall model among the abstractions

### Convergence and gaps

- Operations have converged: every surveyed API has create, exec, and files, and hosted ones add ports, snapshot or pause and resume, TTL renewal, and streaming output
- Two placements of the agent compete: sandbox-as-exec-service driven from outside, as in Inspect, Harbor, SWE-ReX, and E2B, versus agent-server-inside-the-sandbox, as in OpenHands, rivet sandbox-agent, and ACP over stdio
- Network policy has converged on a default action plus an allowlist of hostnames, wildcards, IPs, and CIDRs with optional ports, enforced by a proxy or sidecar
- Credential masking with sentinels swapped at the proxy appears in at least four independent implementations
- There is no shared event schema and no cross-vendor spec; the Agent Client Protocol standardizes sessions, tool calls, permissions, and terminals but has no sandbox concept, and MCP has no sandboxed-execution primitive
- Multi-provider client libraries exist, such as Cased `sandboxes` and the OpenAI Agents SDK sandbox abstraction, but none abstracts network policy across providers

### Multi-agent orchestrators

- Adds real isolation: Docker Sandboxes, OpenHands Agent Canvas with a Docker sandbox option, Sculptor's experimental container backend, and container-use; OpenAI Symphony explicitly declines to mandate sandboxing and defers to Codex and external isolation
- Worktree only: Vibe Kanban (sunsetting per its README), Crystal, Claude Squad, Superset, and cmux; Conductor is `unknown`
- Fit: adjacent to `tsk`; none adds a policy model this repo lacks

## Execution plan

### Sequencing alternatives

The companion architecture doc proposes a different order from the phases below: freeze the security contract first, then build two macOS microVM spikes on Apple Containerization and microsandbox, then extract the broker with a vsock-only transport, then replace live mounts with import and export, and only then add a Linux Cloud Hypervisor backend. It recommends Cloud Hypervisor over Firecracker on Linux for interactive fit and alignment with Apple's Linux backend, and it places gVisor as an optional density tier rather than the first spike.

The two sequences disagree on what to learn first. The phases here test whether plain containers are the bottleneck before paying for a VM boundary; the companion doc treats the VM boundary as settled and tests which macOS substrate to build on. That disagreement is a decision for `m21-capability-model`, not something to resolve in a research note.

### Phase 1. Threat model and normalized capability model

Define:

- Trust boundaries
- Threat actors
- What "good enough" means for local use
- What "high assurance" means for untrusted repos
- A backend capability matrix

Deliverable:

- One scorecard used by every experiment

### Phase 2. Refactor around a backend interface

Do not start with Minikube or Firecracker code.

First define the stable interface:

- Workspace mount model
- Temp space model
- Outbound proxy contract
- Event schema
- Policy schema

Deliverable:

- A backend-agnostic runner contract

### Phase 3. Two low-cost spikes

Build two proof-of-concepts first:

- OS-native backend
- gVisor-backed container backend

Reason:

- Lowest cost way to test whether plain containers are the real bottleneck
- Fastest way to discover where portability breaks

Notes from the 2026-09 refresh:

- The OS-native spike no longer needs to start from scratch: `sandbox-runtime` and nono are working implementations of bubblewrap or Landlock plus Seatbelt with a host-side proxy, and Coder Boundary covers the Linux transparent-proxy variant
- Gemini CLI's `runsc` mode and Inspect's Kubernetes chart are ready-made gVisor configurations to measure against

Deliverable:

- Measured comparison against the current Docker baseline

### Phase 4. One VM-backed container spike

Build a Kata-based proof-of-concept.

Reason:

- Best chance of improving isolation without abandoning OCI workflows

Deliverable:

- Side-by-side comparison of Docker vs gVisor vs Kata

### Phase 5. One heavy-isolation spike

Choose exactly one:

- Direct Firecracker backend
- Full VM backend
- libkrun or Apple `container` microVM backend on Apple Silicon

Reason:

- This tests the upper bound on isolation without dragging in Kubernetes too early

Notes from the 2026-09 refresh:

- Docker Sandboxes is the product benchmark for this phase on macOS, Windows, and Linux, and it may be cheaper to treat as an external backend than to rebuild
- microsandbox, BoxLite, and brood-box show the libkrun path is viable on Apple Silicon; Tart with Softnet shows a full-VM path with VM-level egress filtering but carries an FSL license

Deliverable:

- Reference "maximum isolation" backend

### Phase 6. Kubernetes track, only if justified

Only after phases 1 through 5:

- Add a KubeVirt or Kata-on-Kubernetes experiment
- Add Cilium for L7-aware policy and observability experiments

Reason:

- By this point we will know whether the product needs cluster orchestration or only stronger local isolation

Deliverable:

- Clear answer on whether Kubernetes is a deployment target or just a research distraction

## Proposed milestones

### m21-capability-model

Define the threat model, capability matrix, and backend scorecard.

### m22-backend-interface

Define a backend-agnostic runner contract, event schema, and policy compiler boundary.

### m23-runtime-spikes-lite

Build and compare:

- Current Docker baseline
- OS-native backend, starting from `sandbox-runtime` or nono
- gVisor backend

### m24-runtime-spikes-vm

Build and compare:

- Kata backend
- One heavy-isolation backend such as Firecracker, libkrun, Apple `container`, or a full VM
- Docker Sandboxes as the external benchmark

### m25-kubernetes-track

Only if earlier milestones justify it:

- KubeVirt or Kata on Kubernetes
- Cilium or similar for L7 policy and observability experiments

### m26-decision-and-integration

Choose:

- Default backend
- Optional stronger-isolation backend
- Capability degradation rules per backend
- Policy and logging interfaces to standardize across all backends

## Initial hypotheses

- The current container plus proxy architecture is still the best default baseline for local developer ergonomics
- A normalized backend interface is more important than choosing a new runtime immediately
- gVisor is likely the lowest-cost next backend to test
- Kata is likely the most promising "stronger isolation without abandoning containers" backend
- KubeVirt on Minikube is useful for cluster experiments, but probably the wrong next step for the default local runtime
- OS-native sandboxing is worth exploring for fast local execution, but it is unlikely to become the only portability layer

Added in the 2026-09 refresh:

- Host allowlists plus proxy-side credential injection are now table stakes; this repo's durable differentiators are TLS-inspecting method and path rules, user-owned layered policy, open source, and Intel Mac support
- Docker Sandboxes is the product to benchmark the stronger-isolation backend against, and integrating it as an external backend may beat building a microVM backend
- libkrun is the most plausible open-source microVM substrate for both Linux and Apple Silicon, provided the VMM process is confined
- Harbor's typed policy plus capability declaration is the right shape for the backend contract
- DNS sinkholing is a cheap, composable addition to the current firewall if DNS exfiltration enters the threat model
- Nested vendor sandboxes will be a recurring support question and need a documented per-agent stance

## Open questions

- Should the product optimize first for local single-user developer safety, or for multi-tenant hosted execution?
- Is direct workspace write access a hard requirement, or can high-assurance modes use patch-based writeback?
- Do we want one policy format with graceful degradation, or separate policy levels per backend?
- Is URL path and method enforcement required for arbitrary external HTTPS, or only for approved internal APIs routed through a trusted proxy?
- Is Kubernetes a real target environment, or only a research vehicle for VM-backed runtimes and L7 policy tooling?

Added in the 2026-09 refresh:

- Should Claude Code's and Codex's built-in sandboxes run inside this repo's container, and if so in which mode?
- Should the policy schema gain a credential surface allowlist and SigV4 re-signing to match Claude Code and Infisical Agent Vault?
- Should the firewall adopt a DNS sinkhole, and what breaks for tools that resolve names locally?
- Is Docker Sandboxes an external backend to integrate, a benchmark, or both?
- Which of the vendor policy dialects, if any, should the policy IR compile to?
- Does brood-box's reviewed writeback model fit interactive sessions, or only headless runs?

- Should the first spike test a stronger boundary on macOS, as the companion doc proposes, or test whether plain containers are the bottleneck, as the phases here propose?
- Should TLS inspection be global or per capability, and what does the policy model lose per host when it is off?
- Is a no-NIC vsock-only transport viable for the agents this repo supports, given SSH Git, package managers, and language toolchains?

## Source index

- [OpenAI Codex sandboxing docs](https://developers.openai.com/codex/sandboxing): platform-native sandboxing, writable roots, and local execution modes
- [OpenAI Codex agent approvals and security docs](https://developers.openai.com/codex/agent-approvals-security): `read-only`, `workspace-write`, and `danger-full-access` modes plus network access controls
- [Anthropic Claude Code security docs](https://docs.anthropic.com/en/docs/claude-code/security): local permission model and security guidance
- [Anthropic Claude Code devcontainer docs](https://docs.anthropic.com/en/docs/claude-code/devcontainer): reference container setup with isolation and firewall customization
- [Anthropic Claude Code best practices](https://www.anthropic.com/engineering/claude-code-best-practices): describes Linux `bubblewrap` and macOS `seatbelt`
- [Kubernetes NetworkPolicy docs](https://v1-33.docs.kubernetes.io/docs/concepts/services-networking/network-policies/): de facto standard Kubernetes ingress and egress policy API
- [Gateway API policy attachment](https://gateway-api.sigs.k8s.io/reference/policy-attachment/): standard attachment model for gateway-related policy resources
- [Cilium policy docs](https://docs.cilium.io/en/stable/security/policy/): Kubernetes policy extensions and richer enforcement model
- [RFC 8519 YANG Data Model for Network Access Control Lists](https://datatracker.ietf.org/doc/html/rfc8519): formal ACL model in IETF standards
- [OPA docs](https://www.openpolicyagent.org/docs): policy engine and Rego language
- [Cedar docs](https://docs.cedarpolicy.com/): policy language and authorization engine
- [Apple App Sandbox docs](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox): kernel-enforced app sandbox and entitlements
- [Linux Landlock docs](https://docs.kernel.org/userspace-api/landlock.html): unprivileged filesystem restrictions, TCP bind/connect rules, and IPC scoping
- [Linux seccomp docs](https://docs.kernel.org/userspace-api/seccomp_filter.html): syscall filtering for attack-surface reduction
- [gVisor docs](https://gvisor.dev/docs/): user-space kernel approach for stronger container isolation
- [Kata Containers](https://katacontainers.io/): lightweight VMs with OCI and Kubernetes integration
- [Firecracker](https://firecracker-microvm.github.io/): secure, low-overhead microVMs
- [KubeVirt architecture docs](https://kubevirt.io/user-guide/architecture/): virtualization on top of Kubernetes
- [KubeVirt Minikube quickstart](https://kubevirt.io/user-guide/quickstart_minikube/): local Kubernetes-based VM experiments
- [Cilium HTTP-aware L7 policy docs](https://docs.cilium.io/en/stable/security/network/language/#http-aware-l7-policy): L7 policy model and proxy-based enforcement path
- [Colima README](https://github.com/abiosoft/colima): Lima-backed local VM manager for Docker, containerd, Kubernetes, and Incus
- [Finch architecture docs](https://runfinch.com/architecture/): Lima or WSL plus nerdctl, BuildKit, and containerd
- [Rancher Desktop docs](https://docs.rancherdesktop.io/getting-started/installation/): desktop container and Kubernetes platform
- [Rancher Desktop container engine docs](https://docs.rancherdesktop.io/ui/preferences/container-engine/general/): `containerd` or `dockerd` local runtime selection
- [Rancher Desktop Kubernetes docs](https://docs.rancherdesktop.io/ui/preferences/kubernetes/): built-in Kubernetes enablement
- [Rancher overview](https://ranchermanager.docs.rancher.com/getting-started/overview): Kubernetes management plane, not a local runtime sandbox
- [Podman docs](https://docs.podman.io/en/v4.0.0/markdown/podman.1.html): daemonless container engine with rootless mode
- [Podman machine docs](https://docs.podman.io/en/stable/markdown/podman-machine-start.1.html): VM-backed Podman on macOS and Windows
- [Nix reference manual `sandbox` option](https://nix.dev/manual/nix/stable/command-ref/conf-file): build sandbox behavior and limitations
- [Nix glossary fixed-output derivation](https://nix.dev/manual/nix/stable/glossary): fixed-output derivations have network access
- [NixOS manual container management](https://nixos.org/manual/nixos/unstable/): warning that NixOS containers are not perfectly isolated from the host
- [NixOS manual test driver](https://nixos.org/nixos/manual/index.html): reproducible VM-based system tests using QEMU/KVM or Apple virtualization
- [Devbox docs](https://www.jetify.com/docs/devbox/): isolated, reproducible development environments using Nix
- [Devbox features](https://www.jetify.com/docs/devbox/configuration/): environment definition and configuration model
- [Devbox generated Dockerfile](https://www.jetify.com/docs/devbox/guides/using_devbox_in_docker/): export path into container images
- [Devbox generated devcontainer](https://www.jetify.com/docs/devbox/guides/devbox-with-devcontainer/): export path into devcontainer workflows
- [Development Containers specification](https://containers.dev/): open spec for development containers
- [Development Containers spec reference](https://containers.dev/implementors/spec/): config model and implementation surface
- [VS Code dev containers docs](https://code.visualstudio.com/docs/devcontainers/containers): `devcontainer.json` workflow on top of an underlying container runtime
- [Warden docs](https://docs.warden.dev/): Docker Compose based local development environments
- [Warden installation docs](https://docs.warden.dev/installing.html): requires Docker Engine and Docker Compose
- [Warden configuration docs](https://docs.warden.dev/configuration.html): shared services and per-project configuration overlays
- [Docker Sandboxes overview](https://docs.docker.com/ai/sandboxes/): lightweight microVM-based sandboxes for AI agents
- [Docker Sandboxes architecture](https://docs.docker.com/ai/sandboxes/architecture/): private Docker daemon, host proxy, file synchronization, and isolation model
- [Docker Sandboxes networking and permissions](https://docs.docker.com/ai/sandboxes/networking-and-permissions/): egress policy model, supported rule types, and HTTPS limitations
- [Docker Sandboxes supported providers and IDEs](https://docs.docker.com/ai/sandboxes/providers-and-ides/): provider integration and compatibility surface
- [Unikraft overview](https://unikraft.org/docs): unikernel toolkit and platform overview
- [Unikraft compatibility concepts](https://unikraft.org/docs/concepts/compatibility): POSIX and Linux compatibility model
- [Unikraft local OCI runtime](https://unikraft.org/docs/cli/runtimes/runu): `runu` OCI runtime requirements and limitations
- [Unikraft root filesystem concepts](https://unikraft.org/docs/concepts/filesystems): initramfs and external filesystem options
- [Unikraft local deployment on Firecracker](https://unikraft.org/docs/cli/deploying/deploying-firecracker): Firecracker deployment path
- [Traefik docs overview](https://doc.traefik.io/traefik/): application proxy and edge router
- [Traefik routing docs](https://doc.traefik.io/traefik/routing/overview/): host, path, header, and request-based routing
- [Traefik middleware docs](https://doc.traefik.io/traefik/middlewares/overview/): request processing and control in front of services
- [Varnish documentation](https://docs.varnish-software.com/): reverse caching proxy and HTTP accelerator
- [Varnish overview](https://docs.varnish-software.com/book/what-is-varnish/): sits in front of web servers and caches HTTP responses
- [Ona docs](https://ona.com/docs): management plane, runners, and environment concepts
- [Ona persistent storage](https://ona.com/docs/core-concepts/isolated-environments/persistent-storage): storage attached to the underlying VM
- [Ona port sharing](https://ona.com/docs/core-concepts/isolated-environments/port-sharing): Dev Container network isolation from the VM
- [Ona self-hosted runners](https://ona.com/docs/integrations/compute-providers): AWS and GCP compute integration
- [Ona guardrails](https://ona.com/docs/integrations/agents/customize-guardrails): command guardrails and policy surface
- [Ona leaving Kubernetes](https://ona.com/blog/leaving-kubernetes-behind): public note that the platform moved away from Kubernetes
- [CodeSandbox SDK blog](https://codesandbox.io/blog/introducing-the-codesandbox-sdk): microVMs and developer-oriented sandbox features
- [CodeSandbox Firecracker and snapshots](https://codesandbox.io/blog/how-we-clone-a-running-vm-in-2-seconds): Firecracker and live-clone snapshot design
- [Runloop Devboxes docs](https://docs.runloop.ai/features/devboxes): isolated ephemeral VMs, snapshots, and blueprints
- [Runloop security page](https://www.runloop.ai/security): custom hypervisor and layered security claims
- [Runloop network policies](https://docs.runloop.ai/features/network-policies): outbound network controls
- [exe.dev docs](https://exe.dev/docs): VM product overview, feature list, and use-case docs
- [exe.dev how it works](https://exe.dev/docs/faq/how-exedev-works): Cloud Hypervisor implementation detail, container-image-to-block-device boot model, and proxied networking
- [exe.dev pricing](https://exe.dev/docs/pricing): pooled CPU/RAM, VM count, persistent disk, and cloud pool model
- [Google Cloud GKE Agent Sandbox](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox): Kubernetes-native sandbox controller
- [Google Cloud GKE Sandbox](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/sandbox-pods): gVisor-based pod sandboxing
- [Google Cloud agent sandbox templates and runtime classes](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/agent-sandbox#sandbox_templates): templates, warm pools, and runtimes
- [Modal Sandboxes](https://modal.com/docs/guide/sandbox): secure containers, snapshots, and APIs
- [Modal security model](https://modal.com/security): gVisor-based isolation
- [Daytona Sandboxes](https://www.daytona.io/docs/2.0/sandbox/overview): sandbox concepts and image model
- [Daytona snapshots](https://www.daytona.io/docs/2.0/sandbox/snapshots): snapshot lifecycle
- [Daytona network limits](https://www.daytona.io/docs/2.0/sandbox/network-limits): firewall and network controls
- [E2B docs](https://e2b.dev/docs): fast secure Linux VMs
- [E2B open-source template system](https://e2b.dev/docs/legacy/guide/custom-template): Dockerfile to VM template path
- [E2B infrastructure overview](https://e2b.dev/blog/open-source): Firecracker-based infrastructure and orchestration
- [Blaxel sandboxes](https://docs.blaxel.ai/features/sandboxes): lightweight VMs and sandbox lifecycle
- [Blaxel infrastructure](https://docs.blaxel.ai/getting-started/infrastructure): Mark 3 microVM architecture and standby mode
- [AgentSandbox.co docs](https://docs.agentsandbox.co/): managed code-execution API surface
- [Sandbox0 product page](https://sandbox0.ai/): Kubernetes plus Kata Containers and S3-backed POSIX storage
- [Vercel Sandbox docs](https://vercel.com/docs/vercel-sandbox): Firecracker microVM runtime
- [Vercel Sandbox system model](https://vercel.com/docs/vercel-sandbox/system): runtime image and execution environment
- [Vercel Sandbox firewall](https://vercel.com/docs/vercel-sandbox/firewall): domain and CIDR firewall rules
- [Vercel Sandbox credentials](https://vercel.com/docs/vercel-sandbox/credentials): proxy-side credential brokering
- [Cloudflare Sandbox overview](https://developers.cloudflare.com/sandbox/): sandbox platform overview
- [Cloudflare Sandbox architecture](https://developers.cloudflare.com/sandbox/concepts/how-sandbox-works/): Workers, Durable Objects, and Containers architecture
- [Cloudflare Sandbox runtime](https://developers.cloudflare.com/sandbox/concepts/how-sandbox-works/runtime/): isolated Linux container runtime
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox): Kubernetes CRD and controller for isolated, stateful, singleton sandboxes with stable identity and pluggable runtimes
- [agent-infra/sandbox](https://github.com/agent-infra/sandbox): all-in-one agent sandbox container with browser, files, shell, MCP, VS Code Server, and Jupyter
- [alibaba/OpenSandbox](https://github.com/alibaba/OpenSandbox): general-purpose sandbox platform with multi-language SDKs, unified APIs, Docker and Kubernetes runtimes, ingress and egress components, and secure runtime support
- [jingkaihe/matchlock](https://github.com/jingkaihe/matchlock): experimental microVM sandbox for AI agents with host-side policy and secret injection
- [jingkaihe/matchlock AGENTS guide](https://raw.githubusercontent.com/jingkaihe/matchlock/main/AGENTS.md): concrete backend split, vsock ports, and Linux versus macOS runtime details
- [jingkaihe/matchlock network interception](https://raw.githubusercontent.com/jingkaihe/matchlock/main/docs/network-interception.md): allow-list mutation, hook rules, method and path matching, and secret replacement scope
- [jingkaihe/matchlock VFS interception](https://raw.githubusercontent.com/jingkaihe/matchlock/main/docs/vfs-interception.md): host-side filesystem hook model and SDK-local callback tradeoffs
- [jingkaihe/matchlock lifecycle](https://raw.githubusercontent.com/jingkaihe/matchlock/main/docs/lifecycle.md): SQLite-backed lifecycle state, reconciliation, and cleanup semantics
- [jingkaihe/matchlock ADR-001 local image build](https://raw.githubusercontent.com/jingkaihe/matchlock/main/adrs/001-local-image-build.md): guest defense-in-depth details and privileged-mode consequences
- [jingkaihe/matchlock ADR-003 overlay root](https://raw.githubusercontent.com/jingkaihe/matchlock/main/adrs/003-oci-layer-store-overlay-root.md): proposed OCI layer-aware storage and per-VM writable upper design
- [jingkaihe/matchlock guest sandbox process](https://raw.githubusercontent.com/jingkaihe/matchlock/main/internal/guestruntime/agent/sandbox_proc.go): in-guest namespace, capability-drop, seccomp, and `no_new_privs` implementation
- [strongdm/leash](https://github.com/strongdm/leash): multi-agent sandbox with container wrapping, Cedar policy, Control UI, and experimental native macOS mode
- [strongdm/leash architecture](https://raw.githubusercontent.com/strongdm/leash/main/docs/design/ARCHITECTURE.md): eBPF LSM, MITM proxy, cgroup scoping, MCP observer, and Record, Shadow, and Enforce workflow
- [strongdm/leash Cedar reference](https://raw.githubusercontent.com/strongdm/leash/main/docs/design/CEDAR.md): supported actions and resources, rewrite semantics, MCP policy semantics, and known policy limits
- [strongdm/leash config docs](https://raw.githubusercontent.com/strongdm/leash/main/docs/CONFIG.md): remembered host mounts, env-var forwarding, and supported agent CLI integrations
- [strongdm/leash macOS docs](https://raw.githubusercontent.com/strongdm/leash/main/docs/MACOS.md): Endpoint Security and Network Extension native mode plus macOS feature limits
- [release-engineers/agent-sandbox](https://github.com/release-engineers/agent-sandbox): container-per-agent sandbox with network proxying and patch-based writeback
- [craigbalding/safeyolo](https://github.com/craigbalding/safeyolo): sandbox for Claude Code and Codex with network isolation, credential protection, and audit logging
- [numtide/claudebox](https://github.com/numtide/claudebox): lightweight Claude Code sandbox with Nix integration and shadowed home
- [kenryu42/claude-code-safety-net](https://github.com/kenryu42/claude-code-safety-net): hook and plugin based safety guardrails for Claude Code
- [AshitaOrbis/agent-embassy](https://github.com/AshitaOrbis/agent-embassy): Docker Compose embassy pattern with egress control and output validation
- [schmitthub/openclaw-deploy](https://github.com/schmitthub/openclaw-deploy): hosted OpenClaw gateway deployment with egress filtering and DNS controls
- [dtormoen/tsk](https://github.com/dtormoen/tsk): multi-agent task runner over sandbox containers with branch handoff
- [VirtusLab/sandcat](https://github.com/VirtusLab/sandcat): transparent-proxy and devcontainer based sandbox with secret substitution
- [VirtusLab/sandcat `compose-all.yml`](https://github.com/VirtusLab/sandcat/blob/master/compose-all.yml): app container shares `wg-client` network namespace and mounts workspace plus read-only control files
- [VirtusLab/sandcat `compose-proxy.yml`](https://github.com/VirtusLab/sandcat/blob/master/compose-proxy.yml): dedicated networking container, WireGuard setup, and mitmproxy WireGuard mode
- [VirtusLab/sandcat `mitmproxy_addon.py`](https://github.com/VirtusLab/sandcat/blob/master/scripts/mitmproxy_addon.py): first-match host or method policy plus proxy-side secret substitution and leak blocking
- [VirtusLab/sandcat `.devcontainer/devcontainer.json`](https://github.com/VirtusLab/sandcat/blob/master/.devcontainer/devcontainer.json): concrete VS Code hardening settings and post-start cleanup hook
- [Claude Code sandboxing docs](https://code.claude.com/docs/en/sandboxing): sandboxed Bash tool, filesystem and network settings, credential masking, nested-sandbox mode
- [Claude Code settings reference](https://code.claude.com/docs/en/settings-reference): `sandbox` settings keys and version gates
- [Claude Code permissions docs](https://code.claude.com/docs/en/permissions): permission rule syntax and evaluation order
- [Claude Code hooks docs](https://code.claude.com/docs/en/hooks): `PreToolUse` decisions and managed hooks
- [Claude Code managed settings docs](https://code.claude.com/docs/en/managed-settings): system-level policy delivery paths
- [Claude Code sandbox environments docs](https://code.claude.com/docs/en/sandbox-environments): comparison of Bash sandbox, sandbox runtime, dev container, custom container, VM, and hosted options
- [Claude Code devcontainer docs](https://code.claude.com/docs/en/devcontainer): reference devcontainer status and warnings
- [Claude Code on the web docs](https://code.claude.com/docs/en/claude-code-on-the-web): hosted VM, network levels, allowlist bypass paths
- [Claude Code cloud environments docs](https://code.claude.com/docs/en/cloud-environments): GitHub proxy rules and API credential injection
- [Claude Code self-hosted environments docs](https://code.claude.com/docs/en/self-hosted-environments): operator-enforced egress guidance
- [Anthropic Managed Agents docs](https://platform.claude.com/docs/en/managed-agents/overview): hosted sandbox, `limited` network mode, self-hosted backends
- [Anthropic engineering post on Claude Code sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing): design rationale and prompt-reduction figure
- [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime): open-source `srt` runtime README and settings schema
- [anthropics/claude-code devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer): reference Dockerfile and `init-firewall.sh`
- [anthropics/devcontainer-features](https://github.com/anthropics/devcontainer-features): official `claude-code` devcontainer feature
- [openai/codex linux-sandbox README](https://github.com/openai/codex/tree/main/codex-rs/linux-sandbox): bubblewrap default, legacy Landlock, managed proxy mode
- [openai/codex network-proxy README](https://github.com/openai/codex/tree/main/codex-rs/network-proxy): host rules, `limited` mode, MITM hooks, private-IP blocking
- [openai/codex execpolicy README](https://github.com/openai/codex/tree/main/codex-rs/execpolicy): Starlark `prefix_rule` and `network_rule`
- [OpenAI Codex cloud internet access docs](https://developers.openai.com/codex/cloud/internet-access): domain allowlist presets and HTTP method allowlist (search extract)
- [OpenAI Agents SDK sandboxes guide](https://developers.openai.com/api/docs/guides/agents/sandboxes): `Sandbox` abstraction and hosted providers (search extract)
- [google-gemini/gemini-cli sandbox docs](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/sandbox.md): sandbox modes including `runsc` and Seatbelt profiles
- [google-gemini/gemini-cli policy engine docs](https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/policy-engine.md): TOML tool-call policy tiers
- [github/copilot-cli](https://github.com/github/copilot-cli): approval-only model
- [anomalyco/opencode permissions](https://github.com/anomalyco/opencode): per-tool permission object
- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent): terminal backends and command approval
- [badlogic/pi-mono](https://github.com/badlogic/pi-mono): statement of no built-in permission system and external sandbox options
- [coder/boundary](https://github.com/coder/boundary): method, domain, and path rules, `nsjail` and `landjail` backends, dummy DNS
- [coder/httpjail](https://github.com/coder/httpjail): rule-as-code proxy jail and DNS sinkhole strong mode
- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell): sandbox runtime, policy schema, providers, agent catalog
- [nolabs-ai/nono](https://github.com/nolabs-ai/nono): Landlock and Seatbelt sandboxing, credential proxy with endpoint policy, changelog
- [stacklok/brood-box](https://github.com/stacklok/brood-box): libkrun microVMs, reviewed writeback, egress profiles
- [airutorg/airut](https://github.com/airutorg/airut): mitmproxy plus DNS responder, surrogate secrets, SigV4 re-signing
- [ironsh/iron-proxy](https://github.com/ironsh/iron-proxy): MITM egress proxy with built-in DNS and transform pipeline
- [Infisical/agent-vault](https://github.com/Infisical/agent-vault): explicit-proxy credential broker with surface allowlists
- [superradcompany/microsandbox](https://github.com/superradcompany/microsandbox): libkrun microVMs with placeholder secrets
- [boxlite-ai/boxlite](https://github.com/boxlite-ai/boxlite): embeddable microVM library with VMM confinement and `allow_net`
- [abshkbh/arrakis](https://github.com/abshkbh/arrakis): Cloud Hypervisor microVMs with snapshot and restore
- [inoio/agents-sandbox](https://github.com/inoio/agents-sandbox): VM-backed agent runner with egress profiles
- [wirenboard/agent-vm](https://github.com/wirenboard/agent-vm): repository-scoped GitHub filtering at a TLS-intercepting proxy
- [mensfeld/code-on-incus](https://github.com/mensfeld/code-on-incus): Incus containers with nftables modes and threat detection
- [stefanoginella/aicontainer](https://github.com/stefanoginella/aicontainer): hardened devcontainer details
- [node9-ai/node9-proxy](https://github.com/node9-ai/node9-proxy): hook policy plus iptables egress wall
- [eqtylab/cupcake](https://github.com/eqtylab/cupcake): Rego-to-Wasm hook policy engine
- [stacklok/toolhive](https://github.com/stacklok/toolhive): MCP server containers with outbound permission profiles
- [Zouuup/landrun](https://github.com/Zouuup/landrun): Landlock CLI with port rules
- [dagger/container-use](https://github.com/dagger/container-use): per-agent Dagger containers on git branches
- [rivet-dev/sandbox-agent](https://github.com/rivet-dev/sandbox-agent): in-sandbox control API with universal session schema
- [restyler/awesome-sandbox](https://github.com/restyler/awesome-sandbox): curated list used for discovery when search was unavailable
- [apple/container](https://github.com/apple/container): per-container Linux VMs on Apple Silicon, networking and volume docs
- [apple/containerization](https://github.com/apple/containerization): Swift framework with the Cloud Hypervisor Linux backend
- [containers/libkrun](https://github.com/containers/libkrun): VMM library README and security model
- [containers/krunkit](https://github.com/containers/krunkit): macOS libkrun CLI
- [containers/crun krun handler](https://github.com/containers/crun/blob/main/krun.1.md): OCI containers in libkrun microVMs
- [containers/podman machine docs](https://github.com/containers/podman/blob/main/docs/source/markdown/podman-machine.1.md): provider table with libkrun as macOS default
- [lima-vm/lima docs](https://github.com/lima-vm/lima/tree/master/website/content/en/docs): `vz` and `krunkit` drivers, networking options
- [cirruslabs/tart](https://github.com/cirruslabs/tart): Virtualization.framework VM runner, FSL license, Softnet option
- [openai/softnet](https://github.com/openai/softnet): VM-level packet filter for Tart
- [trycua/cua Lume](https://github.com/trycua/cua/tree/main/libs/lume): Virtualization.framework CLI for computer-use agents
- [nestybox/sysbox](https://github.com/nestybox/sysbox): user-namespace runtime for nested Docker
- [Docker Enhanced Container Isolation docs](https://github.com/docker/docs/tree/main/content/manuals/enterprise/security/hardened-desktop/enhanced-container-isolation): Sysbox-based hardening in Docker Desktop
- [Docker Sandboxes docs source](https://github.com/docker/docs/tree/main/content/manuals/ai/sandboxes): `sbx` CLI, architecture, security, network policies, release notes
- [Docker Desktop release notes](https://github.com/docker/docs/blob/main/content/manuals/desktop/release-notes.md): removal of the `docker sandbox` plugin in 4.80
- [edera-dev/krata](https://github.com/edera-dev/krata): Xen-based per-pod isolation control plane
- [hyperlight-dev/hyperlight](https://github.com/hyperlight-dev/hyperlight): kernel-less micro VM function sandbox
- [google/gvisor user guide](https://github.com/google/gvisor/tree/master/g3doc/user_guide): platforms, GPU, checkpoint and restore, packaging change
- [kata-containers 4.x architecture](https://github.com/kata-containers/kata-containers/tree/main/docs/design/architecture_4.0): Dragonball default VMM
- [firecracker CHANGELOG](https://github.com/firecracker-microvm/firecracker/blob/main/CHANGELOG.md): 1.17 features
- [cloud-hypervisor release notes](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/release-notes.md): v52 and v53 features
- [Linux Landlock documentation](https://github.com/torvalds/linux/blob/master/Documentation/userspace-api/landlock.rst): ABI ladder through 11
- [kubernetes-sigs/network-policy-api](https://github.com/kubernetes-sigs/network-policy-api): `ClusterNetworkPolicy` v1alpha2 and NPEP-133 `domainNames`
- [Cilium DNS policy docs](https://github.com/cilium/cilium/blob/main/Documentation/security/dns.rst): `toFQDNs` requirements
- [agentgateway/agentgateway](https://github.com/agentgateway/agentgateway): CEL MCP authorization and CONNECT egress proxy mode
- [envoyproxy/ai-gateway](https://github.com/envoyproxy/ai-gateway): `MCPRoute` and `BackendSecurityPolicy`
- [docker/mcp-gateway](https://github.com/docker/mcp-gateway): containerized MCP servers with per-profile tool control
- [cedar-policy/cedar CHANGELOG](https://github.com/cedar-policy/cedar/blob/main/cedar-policy/CHANGELOG.md): 4.9 through 4.12 releases
- [open-policy-agent/opa CHANGELOG](https://github.com/open-policy-agent/opa/blob/main/CHANGELOG.md): 1.17 through 1.20 releases
- [MCP specification changelog 2026-07-28](https://github.com/modelcontextprotocol/modelcontextprotocol/tree/main/docs/specification): session removal, `server/discover`, authorization tightening
- [cilium/tetragon enforcement docs](https://github.com/cilium/tetragon/tree/main/docs/content/en/docs/concepts): tracing policy actions and kernel requirements
- [cyberark/secretless-broker](https://github.com/cyberark/secretless-broker): local connector-based credential broker
- [coredns acl plugin](https://github.com/coredns/coredns/tree/master/plugin/acl): source and qtype filtering
- [OpenHands/software-agent-sdk](https://github.com/OpenHands/software-agent-sdk): workspace interface and Agent Server
- [All-Hands-AI/OpenHands 1.5.0 runtime](https://github.com/All-Hands-AI/OpenHands/tree/1.5.0/openhands/runtime): legacy `Runtime` interface and implementations
- [SWE-agent/SWE-ReX](https://github.com/SWE-agent/SWE-ReX): deployment and runtime abstractions
- [UKGovernmentBEIS/inspect_ai sandboxing docs](https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/docs/sandboxing.qmd): `SandboxEnvironment` interface and providers
- [UKGovernmentBEIS/inspect_k8s_sandbox](https://github.com/UKGovernmentBEIS/inspect_k8s_sandbox): gVisor, Cilium FQDN policy, CoreDNS sidecar
- [UKGovernmentBEIS/aisi-sandboxing](https://github.com/UKGovernmentBEIS/aisi-sandboxing): sandboxing toolkit and protocol
- [laude-institute/harbor](https://github.com/laude-institute/harbor): environment contract, capabilities, network policy docs
- [METR/vivaria](https://github.com/METR/vivaria): sandboxing modes and wind-down notice
- [alibaba/OpenSandbox specs](https://github.com/alibaba/OpenSandbox/tree/main/specs): lifecycle OpenAPI, egress sidecar, Credential Vault
- [agentclientprotocol/agent-client-protocol](https://github.com/agentclientprotocol/agent-client-protocol): protocol scope without sandboxing
- [devcontainers/cli CHANGELOG](https://github.com/devcontainers/cli/blob/main/CHANGELOG.md): 0.87 through 0.89
- [devcontainers/spec reference](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md): security-relevant keys
- [imbue-ai/sculptor container backend](https://github.com/imbue-ai/sculptor): experimental container backend
- [openai/symphony SPEC](https://github.com/openai/symphony/blob/main/SPEC.md): explicit deferral of sandboxing
- [daytonaio/daytona](https://github.com/daytonaio/daytona): README notice that development moved to a private codebase
- [Daytona network limits docs](https://www.daytona.io/docs/en/network-limits): `networkBlockAll`, CIDR-only allowlist, `outboundProxyUrl` (search extract)
- [gitpod-io/gitpod](https://github.com/gitpod-io/gitpod): rename to Ona
- [OpenAI announcement on Ona](https://openai.com/index/openai-to-acquire-ona): acquisition agreement (search extract, unverified)
- [Together Code Sandbox docs](https://docs.together.ai/docs/together-code-sandbox): CodeSandbox SDK under Together AI (search extract)
- [Runloop devbox docs](https://docs.runloop.ai/docs/devboxes/start-stop): per-devbox network policies (search extract)
- [Modal sandbox networking docs](https://modal.com/docs/guide/sandbox-networking): domain allowlist beta and policy tightening (search extract)
- [E2B internet access docs](https://docs.e2b.dev/network/internet-access): `allowOut`, `denyOut`, `updateNetwork`, request transforms (search extract)
- [e2b-dev/infra](https://github.com/e2b-dev/infra): self-hosting on GCP and AWS
- [GKE Pod Snapshots docs](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/pod-snapshots): gVisor checkpoint and restore (search extract)
- [Vercel changelog](https://vercel.com/changelog): sandbox persistence GA and firewall matchers (search extract)
- [Cloudflare Managed Agents egress docs](https://github.com/cloudflare/claude-managed-agents/blob/main/docs/applying-egress-policies.md): outbound Worker proxy on microVM and isolate sandboxes
- [Fly.io Sprites](https://fly.io/sprites): Firecracker VMs with continuous checkpoints (search extract)
- [Deno Sandbox security docs](https://docs.deno.com/sandbox/security): Firecracker, `allowNet`, per-host secret substitution
- [AWS AgentCore runtime security docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html): microVM sessions and network modes (search extract)
- [Azure Container Apps sandboxes docs](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/container-apps/sandboxes.md): ACA Sandboxes preview and egress policies
- [Azure Container Apps dynamic sessions docs](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/container-apps/sessions.md): Hyper-V isolation and egress default
- [Koyeb sandboxes docs](https://www.koyeb.com/docs/sandboxes): IP allowlist and redeploy-on-change
- [superserve-ai/superserve](https://github.com/superserve-ai/superserve): Firecracker sandbox with broker
- [buildkite/cleanroom](https://github.com/buildkite/cleanroom): policy-as-code microVM sandboxes with digest-pinned images
- [cased/sandboxes](https://github.com/cased/sandboxes): multi-provider sandbox client
- [kernel/kernel-images](https://github.com/kernel/kernel-images): Chromium on Unikraft browser sandboxes
- [Secure agent sandbox research and architecture](./secure-agent-sandbox-research-and-architecture.md): companion architecture recommendation dated 2026-09-05
- [TencentCloud/CubeSandbox](https://github.com/TencentCloud/CubeSandbox): KVM microVM sandbox service with an eBPF virtual switch and CubeEgress
- [CubeSandbox security proxy doc](https://github.com/TencentCloud/CubeSandbox/blob/master/docs/guide/security-proxy.md): CubeEgress steering, rule fields, injection, and audit schema
- [CubeSandbox network policy docs](https://docs.cubesandbox.com/guide/network-policy): L3 and L4 policy (cited by the companion doc; not read here)
- [microsandbox filesystem security doc](https://github.com/superradcompany/microsandbox/blob/main/docs/security/filesystem.mdx): layered root, virtio-fs broker with `openat2` containment, host-side read-only enforcement, snapshots
- [Firecracker jailer docs](https://github.com/firecracker-microvm/firecracker/blob/main/docs/jailer.md): chroot, cgroups, identity drop, namespaces, rlimits
- [Firecracker seccomp docs](https://github.com/firecracker-microvm/firecracker/blob/main/docs/seccomp.md): per-thread seccomp filters (cited by the companion doc; not read here)
- [libkrun security model](https://github.com/containers/libkrun#security-model): guest and VMM share a security context
- [gVisor security model](https://gvisor.dev/docs/architecture_guide/security/): Sentry design and operator responsibilities (cited by the companion doc; not read here)
- [Apple containerization security advisories](https://github.com/apple/containerization/security/advisories): image extraction, copy, and registry handling advisories (cited by the companion doc; not read here)
- [Confidential Containers](https://github.com/confidential-containers/confidential-containers): TEE-based container protection project
- [Confidential Containers attestation architecture](https://confidentialcontainers.org/docs/attestation/architecture/): Trustee, key broker, attestation (cited by the companion doc; not read here)
- [Kata virtualization guide](https://github.com/kata-containers/kata-containers/blob/main/docs/design/virtualization.md): VMM options
- [Daytona secrets docs](https://www.daytona.io/docs/en/secrets/): host-scoped secret substitution (cited by the companion doc; not read here)
- [Cloudflare sandbox outbound traffic guide](https://developers.cloudflare.com/sandbox/guides/outbound-traffic/): programmable outbound handlers (cited by the companion doc; not read here)
- [AWS AgentCore code interpreter resource management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-resource-management.html): Sandbox, Public, and VPC network modes (cited by the companion doc; not read here)
