# Execution Log: m13.3 - Init And Scaffolding

## 2026-04-02 04:10 UTC - Init and native scaffold generation implemented

Implemented a native Go scaffold layer under `internal/scaffold` for managed compose files, user override scaffolds, layered policy files, devcontainer JSON rendering, and active-target state writes; added reusable Docker image pinning helpers in `internal/docker/images.go`; and replaced the `init` placeholder with a real Cobra command in `internal/cli/init.go` that preserves batch validation, interactive prompting, legacy-layout failures, and state-file updates. Added Go tests for representative CLI and devcontainer scaffolds, devcontainer JSON merge semantics, image pinning behavior, active-target state round trips, interactive and batch init flows, and IDE validation.

**Issue:** The Bash implementation spreads init behavior across many shell helpers, with `yq` performing both YAML mutation and the non-obvious `devcontainer.user.json` deep-merge behavior where arrays append instead of replacing template values.
**Solution:** Centralize generation in `internal/scaffold`, switch to native YAML and JSON manipulation, and add explicit tests for the array-append merge semantics plus the representative generated file invariants.

**Decision:** Preserve the top-level ownership comments from embedded templates in generated YAML files, but treat byte-for-byte comment and key-order reproduction as out of scope so the task can optimize for semantic parity and maintainable native generators.

**Learning:** Local `:local` image refs make it possible to run real end-to-end `agentbox init` checks in a restricted environment without Docker pull access while still exercising the full CLI and scaffold path.

## 2026-04-01 05:12 UTC - Planning complete

Reviewed the `m13.3` section of `docs/plan/milestones/m13-go-cli-rewrite/milestone.md`, `docs/plan/learnings.md`, decision `004`, the completed `m13.2` task artifacts, the Bash init entrypoints in `cli/libexec/init/{init,cli,devcontainer,policy}`, the scaffold helpers in `cli/lib/cli-compose.bash`, `cli/lib/devcontainer.bash`, `cli/lib/composefile.bash`, `cli/lib/policyfile.bash`, `cli/lib/agent.bash`, and `cli/lib/path.bash`, plus the current Bash regression coverage in `cli/test/init/{init,policy,render_devcontainer_json,ensure_devcontainer_runtime_files,regression}.bats` and the embedded template/source template layout under `internal/embeddata` and `cli/templates/`.

The main planning conclusion is that `m13.3` should port the actual scaffold-generation logic into native Go helpers under `internal/scaffold`, keep the embedded template tree as the only source of static content, preserve the current `init` flag and prompt behavior, and verify semantic parity by asserting rendered compose, policy, and devcontainer JSON behavior instead of exact file text.

**Issue:** The Bash implementation relies heavily on `yq` both for YAML mutation and for JSON merge behavior, including details like appending user extension arrays instead of replacing them.
**Solution:** Plan the Go port around native YAML and JSON manipulation, with explicit tests for the known merge semantics and effective-config invariants, so `init` no longer depends on host `yq`.

**Decision:** Keep `m13.3` focused on `init` and its underlying scaffold-generation helpers; do not widen it into `switch`, `edit`, or other stateful lifecycle flows that are already reserved for `m13.4`.

**Learning:** The largest parity risk in `m13.3` is not prompt handling but semantic drift in generated YAML/JSON, especially around relative mount paths, devcontainer layer ordering, optional mounts, and IDE-specific customizations.
