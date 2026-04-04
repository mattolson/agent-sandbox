# Task: m13.5 - Bump And Parity Suite

## Summary

Port `bump` and build the validation layer that proves the Go CLI matches the Bash CLI before distribution is cut over.

## Scope

- Port `bump`, including digest refresh, local-image skip rules, and managed-file-only updates
- Add Go unit tests for shared runtime/config packages
- Add fixture or golden integration tests comparing Go and Bash behavior for key command flows and failure cases
- Update CI so both the legacy Bash CLI and the Go rewrite are exercised during the transition

## Acceptance Criteria

- [ ] `agentbox bump` updates managed compose layers without touching user-owned overrides
- [ ] CI fails when the Go implementation drifts from agreed parity fixtures or semantic invariants
- [ ] The Go test suite covers the core packages used by init/switch/edit/bump paths
- [ ] The Bash CLI remains available long enough to serve as the comparison baseline until cutover

## Applicable Learnings

- The Bash CLI and its existing BATS coverage are still the best behavioral spec, so `m13.5` should compare against that surface directly instead of inferring behavior from milestone text.
- A reusable runtime-layout resolver plus an injectable Docker runner already makes parity-style command testing practical without requiring a live Docker daemon for every Go test.
- Local image refs such as `:local` or short unqualified names are a deliberate escape hatch for restricted environments, so `bump` must preserve the current skip rules rather than treating every image as remotely pinnable.
- Native Go config generation is working as long as parity checks focus on semantic invariants instead of byte-for-byte YAML shape; the parity suite should continue that pattern.
- Strong ownership boundaries are safer than patching arbitrary user files in place, so `bump` should only touch agentbox-managed compose layers and never rewrite shared or agent-specific override files.
- Runtime sync can recreate missing compose layers, but any code path that refreshes files must resolve the compose stack after sync before shelling out to Docker; `m13.5` should keep explicit regression coverage around that behavior.
- Keeping the Bash CLI available as the oracle is part of the rollout strategy, not just a convenience. CI should keep all three layers visible: Bash tests, Go tests, and Bash-vs-Go parity.

## Plan

### Files Involved

- `internal/cli/root.go` - replace the remaining `bump` placeholder with the real command
- `internal/cli/bump.go` - parse flags, detect layout/mode, enumerate managed compose layers, and update pinned images
- `internal/cli/bump_test.go` - command-level tests mirroring Bash `bump` behavior and failure cases
- `internal/scaffold/compose.go` and/or a new `internal/scaffold/bump.go` - reusable read/update helpers for managed compose service images that preserve headers and avoid touching user-owned files
- `internal/runtime/compose.go` and/or `internal/runtime/lifecycle.go` - shared helpers to enumerate initialized managed compose layers for bump/parity fixtures without duplicating layout logic
- `internal/docker/images.go` and tests - reuse the existing pull-and-pin helper, adding only the smallest extra surface if bump needs explicit base-image normalization helpers
- `internal/runtime/*_test.go`, `internal/scaffold/*_test.go`, and `internal/docker/*_test.go` - fill shared-package coverage gaps exposed by the parity task
- `internal/testutil/*.go` - fixture helpers for temp repos, fake docker state, and semantic assertions shared by bump/parity tests
- `testdata/parity/**` - canonical fixture inputs and expected semantic outputs for Bash-vs-Go comparison flows
- `scripts/parity.bash` - harness that runs both CLIs against the same fixtures and compares normalized outputs, file semantics, and stubbed Docker invocations
- `.github/workflows/go-tests.yml` and/or a new parity workflow - ensure Bash tests, Go tests, and parity checks all run during the transition
- `Makefile` - optional local parity entrypoint if it materially improves developer ergonomics
- `docs/plan/milestones/m13-go-cli-rewrite/tasks/m13.5-bump-and-parity-suite/*.md` - living task plan and execution log

### Approach

Treat `m13.5` as two tightly related deliverables instead of unrelated cleanup: port the last missing user-facing command (`bump`) and then lock the rewrite behind a parity gate that compares the Go CLI against the Bash oracle on representative flows. The implementation should stay consistent with earlier tasks: thin Cobra handlers, shared runtime helpers, shared scaffold/config mutators, and semantic tests over exact YAML text.

For `bump`, mirror the current Bash behavior closely rather than inventing a new image-refresh UX. The command should fail fast on unsupported legacy layouts, detect whether the repo is in layered CLI or centralized devcontainer mode, print the same mode-aware status messaging, and then only update managed compose files under `.agent-sandbox/compose/`. The concrete write surface is the base compose file's `proxy` service plus any initialized `agent.<name>.yml` layers' `agent` service images. Shared overrides and agent-specific overrides are explicitly out of scope for mutation. The existing `docker.ResolvePinnedImage` helper already covers the key remote-image behavior: skip local refs, pull remote tags, fall back to an existing local image when pull fails, and otherwise inspect the resolved digest. `bump` should reuse that helper and add only the smallest missing helper needed to normalize digest-pinned references back to their base image before refreshing.

Implement the managed-image update path with native YAML helpers rather than shelling out to `yq`. `internal/scaffold/compose.go` already knows how to load compose files, preserve leading comments, and write documents back safely. `m13.5` should extend that layer with focused service-image getters/setters so both `bump` and its tests can assert semantic updates without duplicating YAML traversal logic inside the command handler. That also keeps the ownership rule obvious: only files intentionally passed into the helper are mutated.

For parity, prefer a dedicated Bash harness plus shared fixtures over trying to encode Bash-vs-Go comparison logic inside ordinary Go unit tests. A shell harness under `scripts/parity.bash` can run `cli/bin/agentbox` and the Go CLI under the same fake `docker`, `EDITOR`, and temp-repo environment, which makes it straightforward to compare command stderr/stdout, exit status, normalized file contents, and Docker invocation shape across both implementations. The fixtures should live under `testdata/parity/` and focus on representative, high-value flows rather than exhaustive duplication of every BATS case: layered and devcontainer `bump`, legacy-layout failure paths, `switch` restart ordering, `edit` target selection, and one or two `init`/runtime resolution flows that protect the core rewrite seams.

The parity suite should assert semantic invariants instead of raw file bytes whenever YAML/JSON output is involved. For example, compare the effective image references written into managed compose files, the set and order of compose layers passed to Docker, the selected user-owned file opened by `edit`, and the presence of expected warning or restart messages. Raw golden files should be limited to simple, stable cases where normalization adds little value. This keeps the suite useful as a drift detector without making every harmless formatting change look like a regression.

In CI, keep the three-layer transition model explicit. The existing Bash BATS workflow should remain in place as the oracle. The existing Go workflow should keep running `go test ./...` and `go build ./cmd/agentbox`. Add the parity suite as the third layer rather than quietly folding it into one of the existing jobs, so failures are easy to interpret and the repo's transition state stays visible. The parity job should trigger on Go CLI code, Bash CLI code, fixture changes, and parity harness changes. The Bash CLI should remain available as a normal executable path for that job and must not be replaced by the Go binary during this milestone.

### Implementation Steps

- [x] Add native helpers for reading and updating compose service images in managed files, plus any minimal runtime helper needed to enumerate the managed layers that `bump` should touch
- [x] Port `agentbox bump` as a real Cobra command that preserves legacy-layout errors, mode detection, local-image skip rules, digest refresh behavior, and managed-file-only writes
- [x] Add Go tests for `bump` command behavior and fill shared-package coverage gaps for runtime/scaffold/docker helpers used by init/switch/edit/bump flows
- [x] Create `testdata/parity/` fixtures and `scripts/parity.bash` to run Bash and Go CLIs against the same temp repos with stubbed external tools and semantic assertions
- [x] Wire the parity suite into CI as a distinct transition gate while keeping the existing Bash and Go workflows visible and intact
- [x] Verify `go test ./...`, `go build ./cmd/agentbox`, the Bash BATS suite, and the new parity harness locally with representative fixtures

### Open Questions

None after execution. The parity gate now lives in its own workflow so Bash oracle, Go tests, and Bash-vs-Go parity remain separately visible in CI.

## Outcome

Implemented the Go `bump` command, added native managed-image read/write helpers plus small shared runtime/docker helpers that keep image refresh logic reusable, created a shared parity harness under `scripts/parity.bash` with fixture repos under `testdata/parity/`, and added a dedicated GitHub Actions parity workflow so the transition now has explicit Bash, Go, and Bash-vs-Go verification layers.

### Acceptance Verification

- [x] `agentbox bump` updates managed compose layers without touching user-owned overrides via `internal/cli/bump_test.go`, `internal/scaffold/compose_image_test.go`, and parity coverage in `testdata/parity/bump-layered`.
- [x] CI fails when the Go implementation drifts from agreed parity fixtures or semantic invariants via `.github/workflows/parity-tests.yml` running `scripts/parity.bash` against shared Bash-vs-Go fixtures.
- [x] The Go test suite covers the core packages used by init/switch/edit/bump paths through the new `internal/cli/bump_test.go`, `internal/runtime/lifecycle_test.go`, `internal/scaffold/compose_image_test.go`, and additional `internal/docker/images_test.go` cases.
- [x] The Bash CLI remains available long enough to serve as the comparison baseline until cutover because parity runs `cli/bin/agentbox` directly as the oracle and the existing Bash workflow remains untouched.

### Learnings

- Bash `edit` flows are not fully non-interactive because `open_editor` binds stdio to `/dev/tty`, so parity automation must provide a pseudo-tty instead of invoking those commands like ordinary batch subprocesses.
- The Bash edit commands detect changes via second-resolution mtimes, which means parity fixtures need an intentional delay before writing editor changes or a real modification can be misclassified as unchanged.
- Semantic parity checks stay maintainable when they compare normalized console output, Docker invocation shape, and rendered config invariants rather than raw YAML/JSON bytes.

### Follow-up Items

- `m13.6` release work should keep the dedicated parity workflow in place until the Go binary has shipped successfully as the primary distribution path and the Bash fallback is formally deprecated.
