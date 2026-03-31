# Task: m13.1 - Go CLI Foundation

## Summary

Establish the Go module, Cobra command skeleton, shared infrastructure, and embedded assets so the rewrite can proceed incrementally without cutting over too early.

## Scope

- Add `go.mod` and a package layout for `cmd/agentbox` plus shared internal packages
- Create the side-by-side repo structure for the rewrite without moving or renaming the existing `cli/` tree
- Create the Cobra root command and subcommand structure mirroring the current CLI surface
- Implement shared helpers for runtime discovery, editor resolution, Docker/Compose invocation, logging, and version metadata
- Keep command handlers thin so core behavior lives in reusable packages rather than inside Cobra wiring
- Add template-sync plumbing so `cli/templates/` stays the source of truth while `internal/embeddata/templates/` is generated for embedding
- Embed CLI templates and other static assets needed by `init` and devcontainer generation so the binary works without a repo checkout
- Keep the Bash CLI available as the reference implementation during the parity phase

## Acceptance Criteria

- [ ] `go build ./cmd/agentbox` succeeds locally and in CI
- [ ] The existing Bash CLI layout remains intact and its test suite still runs without rewrite-specific changes
- [ ] The Go binary can print version/build metadata without relying on `.version` being present next to the binary
- [ ] The Go CLI can be run independently via `go run ./cmd/agentbox` or an equivalent separately named local binary
- [ ] Embedded templates can be loaded from the compiled binary in tests
- [ ] The embedded template mirror is reproducibly generated from `cli/templates/` rather than hand-maintained in two live trees
- [ ] Core runtime logic is callable outside Cobra command handlers so later interactive surfaces are not forced to shell out through the CLI layer
- [ ] The package layout is stable enough that later command ports do not require large-scale refactors

## Applicable Learnings

- Keep `.agent-sandbox/` as the clear ownership boundary for generated runtime files and user-owned overrides; the Go rewrite should preserve that contract rather than redesign it.
- Devcontainer mode should remain a thin IDE-facing shim over the centralized `.agent-sandbox/` runtime files, not become a second source of truth.
- Strong ownership boundaries are safer than patching arbitrary user-edited YAML in place, so the first Go slice should focus on reusable path/state/template helpers rather than ad hoc command logic.
- Security-sensitive policy rendering should keep one merge path; the rewrite should not introduce a second host-side policy merge implementation during the foundation task.
- The existing Bash CLI behavior and test coverage are the best available spec, so `cli/` should remain the oracle while the Go tree grows beside it.

## Plan

### Files Involved

- `go.mod` - define the Go module and direct dependencies such as Cobra
- `go.sum` - lock Go module dependency versions once the module is initialized
- `cmd/agentbox/main.go` - thin Go entrypoint that constructs and executes the Cobra root command
- `internal/cli/root.go` - root command wiring and shared command construction helpers
- `internal/cli/*.go` - top-level and nested Cobra commands that mirror the current CLI surface while keeping handlers thin
- `internal/runtime/*.go` - supported-agent metadata, repo-root discovery, active-target state parsing, project-name helpers, and editor resolution
- `internal/docker/*.go` - reusable subprocess wrappers for `docker` and `docker compose`
- `internal/scaffold/*.go` - embedded template access and future scaffold-oriented helpers shared by later command ports
- `internal/version/*.go` - build metadata model plus local git fallback for developer builds
- `internal/embeddata/embeddata.go` - exported embedded filesystem wrapper for generated templates
- `internal/embeddata/templates/**` - generated mirror of `cli/templates/` used by `go:embed`
- `internal/testutil/*.go` - shared test helpers for fixtures, temp repos, and command execution assertions
- `scripts/sync-go-templates.bash` - reproducibly regenerate the embedded template mirror from `cli/templates/`
- `.github/workflows/go-tests.yml` - Go-specific CI for `go test`, `go build`, and template-sync verification

### Approach

Build the rewrite beside the Bash CLI instead of trying to replace it early. `cmd/agentbox/main.go` should create a Cobra root command with the full current command tree (`init`, `switch`, `edit compose`, `edit policy`, `policy config`, `policy render`, `bump`, `up`, `down`, `logs`, `compose`, `exec`, `destroy`, and `version`), but only `version` and the shared infrastructure need real behavior in this task. Commands that are not ported yet should have explicit placeholders that fail clearly without embedding business logic inside Cobra handlers.

Put real logic in reusable internal packages first. `internal/runtime` should own repo/path discovery, active-target parsing, supported-agent lists, project-name derivation, and editor lookup because those behaviors are already shared across the Bash CLI and will be reused by later Go command ports. `internal/docker` should centralize subprocess setup so later tasks can test Docker/Compose invocation semantics without scattering `exec.Command` calls across the tree. `internal/version` should expose build variables populated by `-ldflags` in CI while falling back to git metadata for `go run` and local repo builds.

Treat template embedding as first-class foundation work. Keep `cli/templates/` as the only hand-edited source tree, add `scripts/sync-go-templates.bash` to regenerate `internal/embeddata/templates/`, and expose that generated mirror through a small `internal/embeddata` package backed by `go:embed`. Add tests that open representative embedded templates from the compiled binary, and add a CI check that reruns the sync script and fails if the generated mirror is stale.

Add a dedicated Go workflow instead of overloading the existing Bash-only test workflow. The new workflow should trigger on Go source, `cli/templates/**`, and the sync script, then run template-sync verification, `go test ./...`, and `go build ./cmd/agentbox`. `cli/run-tests.bash` and `.github/workflows/cli-tests.yml` should remain intact so the Bash CLI stays the behavioral oracle during the parity phase.

Do not widen `m13.1` into image or distribution cutover work. The current sandbox container used for development here does not include `go`, so local verification may need either a host Go toolchain or a developer-local Go-enabled custom image. That is a verification prerequisite, not a reason to start modifying `images/cli/Dockerfile`, `images/build.sh`, or the released Bash distribution path in this task.

### Implementation Steps

- [ ] Add the Go module and baseline package layout under `cmd/` and `internal/`
- [ ] Build the Cobra root command and stub subcommand tree that mirrors the existing CLI surface
- [ ] Implement shared runtime, subprocess, version, and output helpers with focused unit coverage
- [ ] Add template-sync plumbing, generated embedded templates, and tests that prove embedded assets load from the compiled binary
- [ ] Add dedicated Go CI that verifies template sync, `go test ./...`, and `go build ./cmd/agentbox` while leaving Bash tests unchanged
- [ ] Verify `go run ./cmd/agentbox version` and `go build ./cmd/agentbox`, then update this plan if actual file boundaries or package seams need adjustment during execution

### Open Questions

None at planning time. If toolchain availability or package seams prove materially different during execution, capture that as a task update rather than expanding `m13.1` into release-path work.

## Outcome

### Acceptance Verification

Pending execution.

### Learnings

Pending execution.

### Follow-up Items

None yet.
