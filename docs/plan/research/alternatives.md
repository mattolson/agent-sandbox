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
- gVisor
- Kata Containers
- Docker Sandboxes
- OpenSandbox
- Matchlock
- Leash
- `kubernetes-sigs/agent-sandbox`
- CodeSandbox SDK
- E2B
- Runloop
- GKE Agent Sandbox
- Vercel Sandbox
- MCP gateway and host-side registry
- Policy IR direction:
  - Kubernetes `NetworkPolicy`
  - Cilium policy
  - Cedar
  - OPA

### P1: likely to affect packaging, portability, or UX

- Podman rootless
- Colima
- Finch
- Rancher Desktop
- Modal
- Daytona
- Blaxel
- Cloudflare Sandbox
- Sandbox0
- Nix
- NixOS
- Devbox
- devcontainer

### P2: useful adjacent references and edge cases

- Ona
- AgentSandbox.co
- Warden
- Traefik
- Varnish
- Unikraft
- `claudebox`
- `safeyolo`
- `agent-embassy`
- `sandcat`
- `claude-code-safety-net`
- `tsk`

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

Codex documents platform-native sandboxing with `read-only`, `workspace-write`, and `danger-full-access` modes, writable roots, and network off by default for local execution. That is useful, but it is still a provider-specific execution model.

Claude Code documents permission-based local controls and separately offers a reference devcontainer with isolation and firewall rules. Anthropic also describes sandboxing built on Linux `bubblewrap` and macOS `seatbelt`.

Practical implication:

- Vendor-native sandboxes should be treated as defense-in-depth
- They should not be the primary portability layer if the goal is one normalized backend for many agents

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

Practical conclusion:

- Use Kubernetes `NetworkPolicy` as an important compatibility target, not as the project's top-level policy model

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

### Recommendation for this project

Define one internal policy model with graceful degradation.

Compile that model to backend-specific controls such as:

- Kubernetes `NetworkPolicy`
- Cilium policy
- proxy rules
- host firewall rules
- runtime allowlists

Likely policy layers:

- `transport`
  - CIDR
  - port
  - protocol
- `name`
  - hostname
  - wildcard domain
  - service alias
- `http`
  - method
  - path
  - header transforms
  - secret injection
- `execution`
  - allow or deny capabilities by backend

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

## Evaluation criteria

Every candidate backend should be scored against the same criteria:

- Filesystem isolation strength
- Network isolation strength
- Network policy expressiveness
- Runtime syscall and privilege control
- Auditability and logging quality
- Bypass resistance
- Cross-agent compatibility
- macOS local support
- Linux local support
- Apple Silicon support
- Startup latency
- Interactive CLI ergonomics
- CI friendliness
- Operational complexity
- Implementation complexity

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
- `seccomp` is valuable for syscall reduction, but it is not a filesystem or URL policy mechanism

### 2. Hardened containers

Examples:

- Docker or Podman
- Rootless container engines
- Existing proxy sidecar plus firewall model

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

### 4. Direct microVM backend

Examples:

- Firecracker
- Cloud Hypervisor
- Apple Virtualization.framework-based runner on macOS

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

### 5. Full VM backend

Examples:

- Lima or Colima style VM-per-project
- QEMU or libvirt
- Hypervisor-backed local VM running Docker inside

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
- Host-managed agent sandbox product on top of Docker Desktop

What it is:

- Docker documents Sandboxes as lightweight microVMs with a private Docker daemon per sandbox
- The agent runs inside the VM and can build images, run containers, and use Docker Compose without access to the host Docker daemon
- Workspaces are synchronized bidirectionally at the same absolute path rather than bind-mounted

What it is not:

- Not just another container on the host daemon
- Not the same thing as legacy container-based Docker sandboxes
- Not currently a complete answer for fine-grained HTTP path and method policy

Practical use here:

- This is one of the strongest direct comparables to the architecture being explored in this repo
- It validates the idea that "agent needs Docker" is a strong argument for VM-backed isolation rather than host-daemon sharing
- It is especially relevant because it combines:
  - hypervisor-level isolation
  - private daemon per sandbox
  - workspace path preservation
  - outbound HTTP(S) filtering
  - host-side credential injection

Important limitations:

- Docker documents microVM-based sandboxes as requiring macOS or Windows, with Linux using legacy container-based sandboxes
- The current network policy model is host, port, and CIDR oriented, not HTTP path or method aware
- Docker explicitly warns that domain fronting is an inherent limitation of the HTTPS proxying model they use

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

### Direct or near-direct comparables

- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
  - Kubernetes SIG Apps project defining a `Sandbox` CRD and controller for isolated, stateful, singleton workloads with stable identity, persistent storage, lifecycle management, templates, claims, and warm pools
  - Review focus: declarative API shape, CRD model, controller lifecycle, stable identity semantics, pause and resume behavior, warm-pool strategy, and how runtime isolation is delegated to pluggable runtimes such as gVisor or Kata

- [alibaba/OpenSandbox](https://github.com/alibaba/OpenSandbox)
  - General-purpose sandbox platform with multi-language SDKs, unified sandbox APIs, Docker and Kubernetes runtimes, ingress and egress components, and optional secure runtimes including gVisor, Kata, and Firecracker
  - Review focus: protocol and API design, lifecycle server model, runtime abstraction, secure-runtime pluggability, ingress and egress primitives, and how local Docker mode differs from Kubernetes mode

- [jingkaihe/matchlock](https://github.com/jingkaihe/matchlock)
  - Experimental CLI and SDK for running AI agents in ephemeral microVMs with host-managed network allowlisting, MITM-based secret injection, and isolated overlay-backed filesystem snapshots
  - Review focus: microVM lifecycle and startup model, host-side secret boundary, allowlist and interception design, volume snapshot semantics, and Linux versus Apple Silicon portability

- [strongdm/leash](https://github.com/strongdm/leash)
  - Multi-agent sandbox that wraps agents in containers, applies Cedar-defined policy, and combines cgroup-scoped eBPF monitoring with an HTTP MITM proxy plus an experimental native macOS mode
  - Review focus: Cedar-to-runtime compilation, Record, Shadow, and Enforce workflow, eBPF plus proxy control-plane split, MCP policy surface, and Linux versus macOS capability degradation

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
  - Docker Compose sandbox with egress proxy, no host filesystem access, inbox/outbox directories, and host-side output validation
  - Review focus: embassy pattern, output-validation boundary, inbox/outbox workflow, and zero-host-access claims

- [VirtusLab/sandcat](https://github.com/VirtusLab/sandcat)
  - Docker and devcontainer setup using transparent mitmproxy, WireGuard-based traffic capture, host allowlists, and proxy-side secret substitution
  - Review focus: transparent proxy architecture, secret-injection design, WireGuard requirement, DNS and non-HTTP handling, and developer UX

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
  - Could proxy-side secret substitution cover enough of `m18-host-credential-service` to make the helper path strictly secondary, or are there still important workflows that require local credential delivery?
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
  - The split between host policy engine, host VFS service, and microVM runtime is directly relevant to `m19-backend-interface`
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
  - host-side VFS and exec control-plane separation as input to `m19-backend-interface`
  - richer HTTP policy concepts for `m14`, especially method and path matching plus response shaping
  - lifecycle persistence and explicit garbage-collection or reconcile workflows for leaked sandbox resources
- Probably not worth bringing in as-is:
  - feature-triggered interception with allow-all semantics when the allow-list is empty
  - SDK-local callback hooks and especially `dangerous_hook` as primary policy authoring primitives
  - assuming a FUSE or VFS workspace model is the right default for local developer ergonomics before measuring it against a shared mount model
- Research consequence:
  - Treat `matchlock` as a leading reference for the optional stronger-isolation backend and for backend-interface design, not as an argument to replace the current local default before we have comparative measurements
  - It should directly inform `m19-backend-interface` and `m21-runtime-spikes-vm`

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
  - It should inform `m18-capability-model` and `m19-backend-interface`, especially around event schema, policy compilation, and backend capability degradation

## Research backlog: commercial products

These are worth a separate commercial landscape pass. The goal is not just feature comparison. It is to identify the actual substrate each product uses and where its control planes live.

For each commercial product, capture:

- Runtime boundary: container, gVisor, microVM, full VM, isolate, or Kubernetes primitive
- Workspace model: bind mount, sync, persistent disk, snapshot, object storage, or virtual filesystem
- Network model: unrestricted, deny-all, domain policy, CIDR policy, proxy transforms, or VPC integration
- Runtime controls: syscall mediation, VM boundary, container hardening, guardrails, audit logs
- Persistence model: snapshot, suspend-resume, volumes, or external object store
- Hosting model: vendor cloud, self-hosted, BYOC, or hybrid

### Ona

- Public docs describe a two-plane architecture: Ona-hosted management plane plus runners that execute environments and agents in Ona Cloud or in your own AWS or GCP account
- Ona docs state persistent storage is attached to the underlying VM
- Dev Containers can run inside that environment, and the Dev Container network is isolated from the VM by default
- Guardrails, audit logs, and command deny lists are part of the product surface
- Inference: likely VM-backed developer environments with Dev Container support layered on top
- Open question: the exact current runtime substrate is not stated clearly in the public docs; the company also publicly documented leaving Kubernetes, so the current runner implementation needs deeper review

### CodeSandbox SDK

- Official blog says sandboxes run inside microVMs
- Official blog also says the system is built on Firecracker, with custom snapshot and live-clone work
- Key primitives include memory checkpointing, clone-from-snapshot, persistent filesystem with built-in git versioning, and Docker or Docker Compose customization through Dev Containers
- Fit: direct microVM backend with mature snapshotting and developer-environment features

### Runloop

- Docs say Devboxes are isolated, ephemeral virtual machines
- The product site says the infrastructure uses a custom bare-metal hypervisor and describes two layers of security, VM plus container
- Docs describe snapshots, suspend-resume, blueprints, account secrets, object mounts, tunnels, and network policies
- Network policies appear hostname-oriented in the product blog, while some docs also mention SSH access through a transparent proxy
- Fit: VM-backed sandbox platform with additional containerization or image layering inside the VM

### GKE Agent Sandbox

- Google documents this as a Kubernetes controller and API for creating ephemeral runtime environments
- Runtime isolation is achieved with gVisor; Google also documents Kata as another option
- The system introduces Kubernetes-native resources such as `SandboxTemplate`, `SandboxWarmPool`, and router components
- On GKE, the docs position it alongside GKE Sandbox and pod-level checkpoint or restore features
- Fit: Kubernetes-native sandbox controller built on gVisor or Kata, not a standalone local runtime

### Modal Sandboxes

- Modal documents Sandboxes as secure containers for untrusted code
- Modal’s security docs explicitly say Sandboxes are built on top of gVisor
- Network controls include `block_network=True` or CIDR allowlists
- Persistence uses filesystem, directory, and memory snapshots
- Fit: gVisor-backed secure container service with strong snapshot support, but network policy is CIDR based rather than domain or HTTP aware

### Daytona Sandboxes

- Public docs describe isolated sandboxes managed by Daytona, with snapshots built from Docker or OCI images and a declarative image builder
- Sandboxes can run Docker-in-Docker and even a nested k3s cluster
- Docs expose firewall controls and network limits; public examples show block-all and allowlist behavior around network addresses
- Public docs do not clearly spell out whether the underlying runtime is container or VM
- Inference: likely VM-backed or VM-oriented remote development environments, but the public sandbox docs are less explicit than competitors about the exact isolation primitive
- Open question: determine the actual execution boundary and whether security isolation depends on VMs, containers, or both

### E2B

- Docs say each sandbox is a fast, secure Linux VM created on demand
- E2B’s site says each sandbox is powered by Firecracker
- Templates are defined from Dockerfiles or base images and then converted into a microVM
- Fit: Firecracker microVM platform with template building and optional BYOC or self-hosted modes

### Blaxel

- Docs describe sandboxes as lightweight virtual machines
- Infrastructure docs say Mark 3 uses microVMs for low cold starts
- The platform emphasizes standby-mode snapshots that preserve processes and filesystem state, with resume in under 25ms
- Fit: microVM platform with aggressive suspend-resume and snapshot lifecycle management

### AgentSandbox.co

- Public docs describe a secure code-execution API with sessions, artifacts, Python and shell execution, and automatic reproducible dependency installation
- Public docs are much thinner than other vendors’ docs on the actual underlying runtime
- Inference: product appears to be a managed code-execution service rather than a full general-purpose development environment platform
- Open question: determine whether the runtime is container-based, VM-based, or delegated to another substrate

### Sandbox0

- Product page explicitly says it is built on Kubernetes and Kata Containers
- It also says files are persisted to S3 in a POSIX-compatible way and that compute and storage are decoupled
- The product claims E2B API compatibility with a different internal architecture
- Fit: Kubernetes-native Kata backend with externalized filesystem persistence rather than long-lived VM disks

### Vercel Sandbox

- Vercel docs say each sandbox runs in a Firecracker microVM
- System docs say the base image is Amazon Linux 2023 with selectable runtimes and `sudo` available
- Firewall docs expose `allow-all`, `deny-all`, and user-defined network policies with domain and CIDR rules
- Vercel also documents credentials brokering by proxy-side header injection and TLS termination for transformed requests
- Fit: hosted Firecracker microVM service with a more advanced proxy and credential model than most products in this list

### Cloudflare Sandbox SDK

- Cloudflare docs describe a three-layer architecture: Workers, Durable Objects, and Containers
- The sandbox runtime docs say code runs in an isolated Linux container with a full Linux filesystem
- The architecture docs also say the Containers layer provides VM-based isolation and full Linux capabilities
- Fit: Cloudflare-managed sandbox service that exposes durable identities and orchestration through Workers and Durable Objects, with container-like UX over an isolated runtime
- Open question: map the exact boundary between “Containers” marketing, VM isolation claims, and the worker-orchestrated control plane

## Execution plan

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

Reason:

- This tests the upper bound on isolation without dragging in Kubernetes too early

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

### m18-capability-model

Define the threat model, capability matrix, and backend scorecard.

### m19-backend-interface

Define a backend-agnostic runner contract, event schema, and policy compiler boundary.

### m20-runtime-spikes-lite

Build and compare:

- Current Docker baseline
- OS-native backend
- gVisor backend

### m21-runtime-spikes-vm

Build and compare:

- Kata backend
- One heavy-isolation backend such as Firecracker or full VM

### m21-kubernetes-track

Only if earlier milestones justify it:

- KubeVirt or Kata on Kubernetes
- Cilium or similar for L7 policy and observability experiments

### m22-decision-and-integration

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

## Open questions

- Should the product optimize first for local single-user developer safety, or for multi-tenant hosted execution?
- Is direct workspace write access a hard requirement, or can high-assurance modes use patch-based writeback?
- Do we want one policy format with graceful degradation, or separate policy levels per backend?
- Is URL path and method enforcement required for arbitrary external HTTPS, or only for approved internal APIs routed through a trusted proxy?
- Is Kubernetes a real target environment, or only a research vehicle for VM-backed runtimes and L7 policy tooling?

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
