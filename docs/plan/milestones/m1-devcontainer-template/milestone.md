# m1-devcontainer-template

Extract the current `.devcontainer/` into a reusable template that other projects can copy and configure.

## Goals

- Split Dockerfile into base + claude images
- Support two runtime modes: devcontainer (VS Code) and compose (CLI/standalone)
- Define policy YAML schema for domain allowlists
- Extract hardcoded domains to policy file
- Create the "minimal" template (iptables-based, no proxy)
- Document usage for new projects
- Test on a fresh project

## Out of Scope

- Publishing images to GHCR (m2)
- CLI tooling (m3)
- Proxy-based network control (m5)

## Policy Schema

Decided: Option B with services and domains sections.

```yaml
# policy.yaml
services:
  - github  # known service with special handling (fetches from api.github.com/meta)

domains:
  - registry.npmjs.org
  - api.anthropic.com
  - sentry.io
  - statsig.anthropic.com
  - statsig.com
```

The firewall script has handlers for known services. Plain domains get DNS resolution at startup.

## Image Structure

```
images/
├── base/
│   └── Dockerfile          # Tools, firewall, zsh - no agent
└── agents/
    └── claude/
        └── Dockerfile      # FROM base, adds Claude Code
```

The base image includes everything needed for sandboxed development except the agent itself.

## Runtime Modes

Two modes are supported, using the same images but different initialization:

| Mode | Use Case | Firewall Init | Config Files |
|------|----------|---------------|--------------|
| Devcontainer | VS Code users | `postStartCommand` | devcontainer.json |
| Compose | CLI/standalone | Entrypoint script | docker-compose.yml |

VS Code bypasses Docker entrypoints, so devcontainer mode requires explicit `postStartCommand`. The entrypoint script is idempotent (checks for existing rules before running).

## Template Structure

Templates are organized by network approach, then by agent. Each template includes both devcontainer and compose configs:

```
devcontainer/templates/
├── minimal/                    # iptables-based network control
│   ├── README.md               # Docs for minimal approach
│   └── claude/
│       ├── .devcontainer/
│       │   ├── devcontainer.json
│       │   └── Dockerfile      # FROM agent-sandbox-claude
│       ├── docker-compose.yml  # Standalone mode
│       ├── policy.yaml         # User-customizable allowlist
│       └── README.md           # Claude-specific notes
└── proxy-locked/               # m5: proxy-based network control
    └── claude/
        └── ...
```

For m1, we create `minimal/claude/`. Other agents (codex, opencode) added in m4.

## Tasks

### m1.1-policy-schema ✓

Define the YAML schema for policy files.

- Create example policy.yaml with services + domains structure
- Document the schema (what services are supported, domain format)

### m1.2-split-images ✓

Split current Dockerfile into base + claude, add compose support.

- Create images/base/Dockerfile with tools, firewall deps, zsh, entrypoint
- Create images/agents/claude/Dockerfile extending base with Claude Code
- Add docker-compose.yml for standalone mode
- Add images/build.sh for local builds
- Update devcontainer to use new image structure
- Verify both modes work (devcontainer and compose)

### m1.3-policy-file

Extract hardcoded domains to policy.yaml and update firewall to read from it. (Merged from original m1.3 + m1.4)

- Create `images/base/policy.yaml` with default allowlist
- Bake policy into image at `/etc/agent-sandbox/policy.yaml`
- Update init-firewall.sh to parse policy via yq
- Handle "services" section (github-meta lookup)
- Handle "domains" section (DNS resolution)
- Allow optional override via read-only mount from host

Security: Policy file owned by root, not writable by dev user. Override must be mounted read-only from outside workspace.

### m1.5-create-template

Create the minimal/claude template structure with both runtime modes.

- Set up devcontainer/templates/minimal/claude/
- Include .devcontainer/ with devcontainer.json and Dockerfile
- Include docker-compose.yml for standalone mode
- Include policy.yaml (shared by both modes)
- Template Dockerfile references local image build or placeholder for GHCR

### m1.6-template-docs

Document template usage.

- README with quickstart (copy to project, customize policy, open in devcontainer)
- Document policy customization (adding domains, removing services)
- Document testing/verification steps

### m1.7-test-template

Validate template on a fresh project.

- Copy template to a test project outside this repo
- Test devcontainer mode: verify VS Code workflow works
- Test compose mode: verify standalone workflow works
- Verify firewall blocks unauthorized domains in both modes
- Verify allowed domains work in both modes

## Dependencies

None (first milestone)

## Definition of Done

- [x] Base and claude Dockerfiles exist and build
- [x] Both runtime modes work (devcontainer and compose)
- [ ] Policy YAML schema defined and documented
- [ ] Firewall script reads from policy file
- [ ] Template in devcontainer/templates/minimal/ is complete (both modes)
- [ ] README documents usage for both modes
- [ ] Template tested on fresh project
