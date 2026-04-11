# Milestone: m13 - Go CLI Rewrite

## Goal

Replace the Bash `agentbox` CLI with a Go implementation built on Cobra, while preserving the current layered runtime model and command behavior. The end state is a self-contained binary distribution for macOS and Linux, stronger automated testing, and no host-side `yq` dependency.

Current status: completed. The side-by-side transition described below is historical context from the rewrite phase; the
legacy Bash CLI, parity harness, and Docker CLI image distribution were removed in the final cleanup after cutover.

## Scope

**Included:**
- Go-based implementation of the current `agentbox` command surface: `init`, `switch`, `edit compose`, `edit policy`, `policy config`/`render`, `bump`, `up`, `down`, `logs`, `compose`, `exec`, `destroy`, and `version`
- Cobra command tree, shared runtime/config packages, and version/build metadata
- Native YAML/JSON handling for compose, policy, and devcontainer generation so the host no longer needs `yq`
- Embedded templates/assets needed for binary-only distribution outside a repo checkout
- Cross-compiled binaries for macOS (`arm64`, `amd64`) and Linux (`arm64`, `amd64`)
- Test coverage that treats the current Bash CLI as the behavioral reference until cutover is complete
- Documentation and release workflow updates that make the Go binary the primary installation path

**Excluded:**
- New CLI features from later milestones (`m14` through `m18`)
- Changes to the layered runtime ownership model or proxy policy format
- Windows support
- Replacing the proxy-side `render-policy` helper with a separate host-side policy merge implementation
- Homebrew packaging and tap/formula maintenance
- Installer-script automation such as a `curl | sh` flow

## Applicable Learnings

- Keep `.agent-sandbox/` as the clear ownership boundary for generated runtime files and user-owned overrides; the Go rewrite should preserve that contract rather than redesign it.
- Devcontainer mode should remain a thin IDE-facing shim over the centralized `.agent-sandbox/` runtime files, not become a second source of truth.
- Strong ownership boundaries are safer than patching arbitrary user-edited YAML in place. The Go CLI should continue to distinguish managed files from user-owned layers.
- Security-sensitive policy rendering should keep one merge path. `agentbox policy config` should continue to invoke the proxy's runtime `render-policy` logic instead of creating a divergent host implementation.
- The existing Bash CLI behavior and test coverage are the best available spec. The rewrite should prove parity against that behavior before the Go binary becomes the default distribution.

## Side-by-Side Development Strategy

The Go rewrite should live beside the Bash CLI until the final cutover. `cli/` remains the reference implementation and fallback distribution path during the parity phase; the rewrite should not move, rename, or overwrite it early.

```text
/
├── cli/                          # existing Bash CLI, kept intact until cutover
│   ├── bin/agentbox
│   ├── lib/
│   ├── libexec/
│   ├── templates/
│   └── test/
├── cmd/
│   └── agentbox/                 # Go main package
├── internal/
│   ├── cli/                      # Cobra wiring and command registration
│   ├── runtime/                  # repo detection, paths, active-agent state
│   ├── docker/                   # docker / compose invocation wrappers
│   ├── scaffold/                 # init/switch/edit file generation
│   ├── policy/                   # policy targeting + render-policy bridge
│   ├── version/                  # build metadata
│   ├── testutil/                 # shared Go test helpers
│   └── embeddata/
│       └── templates/            # generated mirror of cli/templates for go:embed
├── testdata/
│   └── parity/                   # shared fixtures for Bash-vs-Go comparisons
├── scripts/
│   ├── sync-go-templates.bash    # copies cli/templates into embeddata/templates
│   └── parity.bash               # runs both CLIs against the same fixtures
└── go.mod
```

- `cli/` stays as the Bash oracle until m13.6, and its existing tests continue to run unchanged.
- Go code lives in standard `cmd/` plus `internal/` layout, grouped by runtime concern rather than by one-to-one Bash file translation.
- `cli/templates/` remains the single source of truth during the transition. The embedded Go copy is generated for `go:embed`; developers should not hand-edit `internal/embeddata/templates/`.
- Local development should run the Go CLI as `go run ./cmd/agentbox` or a separately named binary such as `agentbox-go`. `cli/bin/agentbox` should not be replaced until the final cutover.
- CI should run three layers in parallel during the transition: existing Bash tests, `go test ./...`, and a parity suite that exercises both CLIs against the same fixtures.

## Future TUI Compatibility

`m13` should future-proof the CLI for `m17`, but it should not choose the `m17` UI architecture prematurely.

- Cobra helps as a command entrypoint for future interactive subcommands, but it is not itself a TUI framework.
- The Go rewrite should keep Cobra handlers thin and move runtime, policy, logging, and unblock logic into reusable internal packages that can back both standard CLI commands and a future TUI.
- `m17` should choose its TUI framework independently during milestone planning once the monitoring workflow is better defined.
- `Bubble Tea` is the most likely default choice for a future full-screen TUI, but that remains a likely direction rather than an `m13` commitment.

## Tasks

### m13.1-go-foundation

**Summary:** Establish the Go module, Cobra command skeleton, shared infrastructure, and embedded assets so the rewrite can proceed incrementally without cutting over too early.

**Scope:**
- Add `go.mod` and a package layout for `cmd/agentbox` plus shared internal packages
- Create the side-by-side repo structure for the rewrite without moving or renaming the existing `cli/` tree
- Create the Cobra root command and subcommand structure mirroring the current CLI surface
- Implement shared helpers for runtime discovery, editor resolution, Docker/Compose invocation, logging, and version metadata
- Keep command handlers thin so core behavior lives in reusable packages rather than inside Cobra wiring
- Add template-sync plumbing so `cli/templates/` stays the source of truth while `internal/embeddata/templates/` is generated for embedding
- Embed CLI templates and other static assets needed by `init` and devcontainer generation so the binary works without a repo checkout
- Keep the Bash CLI available as the reference implementation during the parity phase

**Acceptance Criteria:**
- `go build ./cmd/agentbox` succeeds locally and in CI
- The existing Bash CLI layout remains intact and its test suite still runs without rewrite-specific changes
- The Go binary can print version/build metadata without relying on `.version` being present next to the binary
- The Go CLI can be run independently via `go run ./cmd/agentbox` or an equivalent separately named local binary
- Embedded templates can be loaded from the compiled binary in tests
- The embedded template mirror is reproducibly generated from `cli/templates/` rather than hand-maintained in two live trees
- Core runtime logic is callable outside Cobra command handlers so later interactive surfaces are not forced to shell out through the CLI layer
- The package layout is stable enough that later command ports do not require large-scale refactors

**Dependencies:** None

**Risks:** Choosing packages that mirror the old Bash file tree too literally could make later changes awkward. Favor runtime concerns and data flows over one-to-one file translation. Renaming or restructuring `cli/` too early would also make parity harder to prove and increase churn for no real gain.

### m13.2-runtime-commands

**Summary:** Port the commands that primarily discover the active runtime and shell out to Docker/Compose, giving the Go CLI real end-to-end behavior early.

**Scope:**
- Port `compose`, `up`, `down`, `logs`, `exec`, `policy config`, `policy render`, and `version`
- Recreate layered compose discovery and legacy-layout guardrails
- Preserve passthrough argument handling, TTY behavior, and environment propagation expected by the current CLI
- Keep `policy config` on the existing proxy-driven render path (`docker compose run ... render-policy`) rather than duplicating merge logic in Go

**Acceptance Criteria:**
- The Go CLI resolves the same effective compose stack as the Bash CLI for representative CLI-mode and devcontainer fixtures
- Docker/Compose commands invoked by the Go implementation match the current semantics for passthrough and runtime targeting
- `agentbox policy config` still renders through the proxy helper and returns the effective policy
- Legacy single-file layouts fail fast with guidance equivalent to the current UX

**Dependencies:** m13.1

**Risks:** TTY and subprocess behavior can differ subtly across macOS and Linux. Catch this with integration coverage on both platforms before porting more stateful commands.

### m13.3-init-and-scaffolding

**Summary:** Port `init` and the underlying file-generation logic with native YAML/JSON handling, preserving the layered runtime model and current project scaffolding behavior.

**Scope:**
- Port interactive and batch `init` flows
- Generate CLI-mode and devcontainer-mode runtime files under the current `.agent-sandbox/` and `.devcontainer/` layout
- Replace `yq`-based host mutations with native Go handling for policy files, compose layers, and devcontainer JSON
- Preserve agent, mode, and IDE prompting plus optional mount scaffolding behavior
- Keep image pull and digest pinning behavior performed during `init`

**Acceptance Criteria:**
- `agentbox init` works for representative agents in both CLI and devcontainer modes
- Generated runtime files are semantically equivalent to the Bash CLI output for the same inputs
- No host `yq` dependency is required for init-related flows
- The binary works outside a repo checkout because all required templates are embedded or otherwise packaged with it

**Dependencies:** m13.1, m13.2

**Risks:** YAML and JSON generation can drift from existing output in small but important ways, especially around layered overrides and IDE-specific devcontainer details.

### m13.4-stateful-lifecycle-commands

**Summary:** Port the commands that mutate existing initialized projects while preserving user-owned state, restart semantics, and layered ownership boundaries.

**Scope:**
- Port `switch`, `edit compose`, `edit policy`, and `destroy`
- Preserve active-agent tracking, lazy scaffolding of per-agent runtime files, and devcontainer refresh behavior
- Recreate edit-time change detection, automatic proxy/container restart behavior, and warning paths
- Preserve confirmation/force flows for destructive cleanup

**Acceptance Criteria:**
- `agentbox switch` preserves shared and agent-specific overrides while refreshing the selected runtime correctly
- `agentbox edit compose` and `agentbox edit policy` target the same user-owned files and apply the same restart/warning semantics as today
- `agentbox destroy` removes layered runtime files and compose resources with the current confirmation behavior
- Regression coverage exists for legacy-layout failures and same-agent refresh paths

**Dependencies:** m13.2, m13.3

**Risks:** This is the highest-risk area for accidental user-data loss or clobbered overrides. The task should lean heavily on fixture-based tests and preserve-file assertions.

### m13.5-bump-and-parity-suite

**Summary:** Port `bump` and build the validation layer that proves the Go CLI matches the Bash CLI before distribution is cut over.

**Scope:**
- Port `bump`, including digest refresh, local-image skip rules, and managed-file-only updates
- Add Go unit tests for shared runtime/config packages
- Add fixture or golden integration tests comparing Go and Bash behavior for key command flows and failure cases
- Update CI so both the legacy Bash CLI and the Go rewrite are exercised during the transition

**Acceptance Criteria:**
- `agentbox bump` updates managed compose layers without touching user-owned overrides
- CI fails when the Go implementation drifts from agreed parity fixtures or semantic invariants
- The Go test suite covers the core packages used by init/switch/edit/bump paths
- The Bash CLI remains available long enough to serve as the comparison baseline until cutover is complete

**Dependencies:** m13.2, m13.3, m13.4

**Risks:** Raw file-by-file golden tests can become brittle. Prefer semantic assertions for YAML/JSON structure and effective Docker/Compose invocations where possible.

### m13.6-release-cutover-and-docs

**Summary:** Make the Go binary the supported distribution path and update project docs, CI, and release automation to match.

**Scope:**
- Add build/release automation for macOS and Linux binaries (`amd64`, `arm64`)
- Publish versioned GitHub release archives plus checksums for the supported platforms
- Update installation and upgrade docs to use direct binary downloads from GitHub Releases as the primary install path instead of the Docker CLI image and host `yq`
- Keep the Docker CLI image path as a deprecated fallback during the transition instead of removing it immediately
- Switch the repo's primary `agentbox` implementation path to the Go binary once parity gates pass
- Clean up obsolete Bash-only distribution plumbing after the first successful Go release path is validated
- Explicitly defer Homebrew packaging and installer-script automation to a fast-follow milestone after the binary release path is stable

**Acceptance Criteria:**
- A tagged release produces downloadable archives and checksums for all supported platforms and architectures
- README, `cli/README.md`, troubleshooting docs, and changelog document manual binary install from GitHub Releases as the primary path and no longer instruct users to install `yq`
- The Go binary can manage a project end-to-end using the documented install flow
- The Docker CLI image path remains available only as a clearly deprecated fallback during the transition
- Homebrew and installer-script work are called out as fast-follow, not hidden inside m13 scope

**Dependencies:** m13.5

**Risks:** Cutting over distribution before parity is proven could strand users without an escape hatch. Delay removal of the old path until the new release flow has succeeded on real artifacts.

## Execution Order

1. **m13.1** - Foundation first: module layout, shared helpers, embedded assets, and version metadata
2. **m13.2** - Port low-risk runtime commands to validate Docker/Compose execution and runtime discovery early
3. **m13.3** - Port `init` and scaffolding once the shared runtime and asset-loading model are stable
4. **m13.4** - Port stateful lifecycle commands (`switch`, `edit`, `destroy`) after `init` is in place
5. **m13.5** - Port `bump` and finish the parity/CI layer before cutover
6. **m13.6** - Release binaries, update docs, and deprecate the old distribution path last

Parallelization is limited because the later tasks depend on the shared runtime and scaffolding model established early. The most realistic overlap is drafting release/docs work while parity coverage is finishing.

Critical path: `m13.1 -> m13.2 -> m13.3 -> m13.4 -> m13.5 -> m13.6`.

## Risks

- **Behavioral drift from the Bash CLI:** The current Bash implementation is the de facto spec. Mitigation: keep it in place during transition and compare the Go CLI against fixtures and semantic invariants.
- **Embedded asset and path assumptions:** The Bash CLI assumes a repo checkout. A distributed binary cannot. Mitigation: embed templates and test outside-repo execution explicitly.
- **Cross-platform subprocess differences:** Editor launching, TTY handling, and `docker compose` behavior vary across macOS and Linux. Mitigation: run integration coverage on the supported platform matrix before cutover.
- **YAML/JSON mutation edge cases:** Native handling removes `yq`, but it also risks subtle config drift. Mitigation: assert semantic output for generated compose, policy, and devcontainer files.
- **Premature distribution cutover:** Replacing the Docker CLI image too early could leave users without a fallback. Mitigation: cut over only after parity and release automation are proven.
- **Install friction before package-manager support exists:** Manual binary install is acceptable for m13, but it raises the bar slightly for some users. Mitigation: document a simple download-plus-checksum flow and treat Homebrew/installer automation as fast-follow once the release artifacts settle.

## Definition of Done

- The Go `agentbox` implementation covers the current user-facing command surface with parity for representative CLI-mode and devcontainer workflows
- Host-side `yq` is no longer required for documented CLI workflows
- Binary releases exist for macOS (`arm64`, `amd64`) and Linux (`arm64`, `amd64`)
- GitHub Releases is the documented primary install path, with checksums and manual install instructions
- CI covers Go unit tests plus integration/parity verification for the rewrite
- Project documentation points users to the Go binary as the primary installation path
- The old Bash CLI and Docker CLI image distribution paths are removed after the Go cutover is validated
- Homebrew and installer-script automation are explicitly deferred to fast-follow work

## Changes

### 2026-04-10: Removed the legacy Bash CLI path

Removed the old `cli/` implementation, parity harness, template-sync plumbing, and Docker CLI image distribution after
the Go binary release path was established.

### 2026-03-28: Clarified installation strategy

Documented GitHub Releases binary downloads as the primary m13 install path, kept the Docker CLI image as a temporary deprecated fallback, and explicitly deferred Homebrew plus installer-script automation to fast-follow work.

### 2026-03-28: Defined side-by-side rewrite layout

Documented that the Go rewrite will live under `cmd/`, `internal/`, `testdata/`, and `scripts/` while `cli/` remains intact as the Bash reference implementation until the final m13 cutover.

### 2026-03-28: Added future TUI note

Documented that m13 should keep core logic reusable for a future m17 interactive TUI, while deferring framework selection to m17 planning with Bubble Tea noted as the likely default.
