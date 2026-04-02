# Task: m13.3 - Init And Scaffolding

## Summary

Port `init` and the underlying file-generation logic with native YAML/JSON handling, preserving the layered runtime model and current project scaffolding behavior.

## Scope

- Port interactive and batch `init` flows
- Generate CLI-mode and devcontainer-mode runtime files under the current `.agent-sandbox/` and `.devcontainer/` layout
- Replace `yq`-based host mutations with native Go handling for policy files, compose layers, and devcontainer JSON
- Preserve agent, mode, and IDE prompting plus optional mount scaffolding behavior
- Keep image pull and digest pinning behavior performed during `init`

## Acceptance Criteria

- [ ] `agentbox init` works for representative agents in both CLI and devcontainer modes
- [ ] Generated runtime files are semantically equivalent to the Bash CLI output for the same inputs
- [ ] No host `yq` dependency is required for init-related flows
- [ ] The binary works outside a repo checkout because all required templates are embedded or otherwise packaged with it

## Applicable Learnings

- Keep `.agent-sandbox/` as the clear ownership boundary for generated runtime files and user-owned overrides; the Go rewrite should preserve that contract rather than redesign it.
- Devcontainer mode should remain a thin IDE-facing shim over the centralized `.agent-sandbox/` runtime files, not become a second source of truth.
- Relative paths in Docker Compose files are resolved from the compose file's directory, not the project root, so generated compose mounts and `dockerComposeFile` entries must continue to be written relative to `.agent-sandbox/compose/` and `.devcontainer/`.
- Shell-sourced state files should write user-facing values with shell escaping (`%q`) or later reads can break on spaces and special characters.
- Policy files that control security must live outside the workspace and be mounted read-only; scaffolding should preserve the current policy layout and mount points rather than collapsing them into a different structure.
- Devcontainer-specific policy rules should stay as additive layered policy files under `.agent-sandbox/policy/`, not a second standalone policy source.
- The runtime-command port kept runtime sync intentionally minimal, so `m13.3` is the right place to port the managed-file generation and refresh logic that later lifecycle commands will rely on.
- The existing Bash init regression tests are the best available semantic spec, especially for optional mounts, image pinning, IDE-specific differences, and devcontainer JSON merge behavior.

## Plan

### Files Involved

- `go.mod` / `go.sum` - add the native YAML dependency used by the scaffold generators and tests
- `internal/cli/root.go` - replace the `init` placeholder with the real command wiring
- `internal/cli/init.go` - CLI parsing for batch and interactive init flows
- `internal/cli/init_test.go` - command-level tests for validation, prompting, and state-file writes
- `internal/scaffold/templates.go` - keep embedded templates as the source for native generation helpers
- `internal/scaffold/init.go` - orchestrate CLI-mode and devcontainer-mode initialization using embedded templates and native writers
- `internal/scaffold/compose.go` - native YAML handling for base, agent, override, and mode-specific compose files
- `internal/scaffold/policy.go` - native YAML handling for user policy scaffolds and managed devcontainer policy files
- `internal/scaffold/devcontainer.go` - native JSON merge/render logic for `devcontainer.json` and `devcontainer.user.json`
- `internal/runtime/state.go` - native active-target state writing and shell-safe value persistence
- `internal/runtime/devcontainer.go` - reusable devcontainer IDE validation shared by init and later lifecycle commands
- `internal/docker/invocation.go` or `internal/docker/images.go` - image pull and digest pinning helpers reused by init
- `internal/runtime/compose.go` - reuse or extend layout-path helpers needed by the scaffold writers
- `internal/testutil/*.go` - temp-repo, fixture, and command-runner helpers shared by init tests
- `cli/templates/**` - source templates already embedded into the Go binary; no new source-of-truth tree should be introduced
- `docs/plan/milestones/m13-go-cli-rewrite/tasks/m13.3-init-and-scaffolding/*.md` - living task plan and execution log

### Approach

Port `init` as a thin Cobra command over native scaffold helpers rather than translating the Bash scripts line by line. The command should preserve the current flag surface (`--agent`, `--mode`, `--ide`, `--name`, `--path`, `--batch`), the same validation and batch-mode requirements, the same legacy-layout guardrails, and the same active-target state semantics. Interactive mode should keep the current prompt order and defaults: derive the base project name from the target path, prompt for name/agent/mode, and prompt for IDE only in devcontainer mode.

Move file generation into `internal/scaffold` and use the embedded template tree from `internal/embeddata` as the only source of template content. For files that are copied verbatim when missing, such as `user.override.yml`, `user.agent.<agent>.override.yml`, `user.policy.yaml`, and `devcontainer.user.json`, use the embedded template bytes directly. For managed files that the Bash CLI currently mutates with `yq`, parse the embedded templates into native data structures, apply the same semantic changes in Go, and then write them back out. YAML should use a native YAML library so we can update service images, project names, volumes, environments, and devcontainer-specific policy service lists without requiring host `yq`. JSON should use the standard library plus an explicit merge routine that preserves the current `devcontainer.user.json` overlay semantics, especially array appends for VS Code extensions.

Keep image pull and digest pinning behavior in scope for this task. The Go port should reuse the existing Docker subprocess seam to implement the current `pull_and_pin_image` behavior: skip digest resolution for `:local` or short local names, try `docker pull` for remote images, fall back to an existing local image if pull fails, and otherwise inspect the resolved digest. That logic belongs in a reusable helper because later `bump` work will need similar behavior. `init` should continue writing pinned image references into generated managed compose files.

For native compose and policy generation, aim for semantic equivalence rather than byte-for-byte reproduction. That means the same services, environment values, volumes, policy mount targets, named volumes, devcontainer compose layers, and IDE-specific differences should be present in the rendered effective config, even if formatting or key order differs slightly. The best verification path is to mirror the existing Bash regression tests in Go: generate files into temp repos, render effective compose stacks where possible, and assert semantic invariants rather than exact YAML text. For devcontainer JSON, explicitly test the current merge behavior where user arrays append to template arrays instead of replacing them.

The m13.2 runtime-sync seam should stay narrow in this task. I plan to implement the actual scaffold-generation logic here and only wire in the parts required for `init` itself, plus any minimal hooks needed so the already-ported runtime commands can call back into the new scaffold layer later. I do not plan to port `switch`, `edit`, or `destroy` behavior as part of m13.3; those remain in m13.4.

### Implementation Steps

- [x] Add native scaffold helpers for managed compose, user override, policy, devcontainer JSON, and active-target state generation using embedded templates
- [x] Port image pull and digest pinning behavior into reusable Go helpers without depending on host `yq`
- [x] Port batch and interactive `init` flow onto Cobra, preserving validation, prompt order, defaults, and legacy-layout failures
- [x] Add Go tests for batch validation, interactive prompting, state-file writes, policy/devcontainer rendering semantics, and representative CLI/devcontainer scaffold outputs
- [x] Verify that generated runtime files are semantically equivalent to the Bash output for representative agents and IDE modes
- [x] Run `go test ./...`, `go build ./cmd/agentbox`, and representative `go run ./cmd/agentbox init ...` checks, then update the plan if file boundaries or helper seams need adjustment during execution

### Open Questions

None after execution. The implemented writers preserve the important top-level ownership comments from the embedded templates while treating deeper comment-perfect reproduction as out of scope for this slice.

## Outcome

### Acceptance Verification

- [x] `agentbox init` works for representative agents in both CLI and devcontainer modes through `internal/scaffold/init_test.go`, `internal/cli/init_test.go`, and end-to-end batch `go run ./cmd/agentbox init ...` checks using local image refs.
- [x] Generated runtime files are semantically equivalent to the Bash CLI output for representative inputs via direct assertions over the generated compose, policy, state, and devcontainer JSON files in `internal/scaffold/init_test.go`.
- [x] No host `yq` dependency is required for init-related flows; the Go init tests and end-to-end checks pass without invoking `yq`.
- [x] The binary works outside a repo checkout because it reads embedded templates, verified by building a standalone `agentbox` binary and running `init` against a temp project outside `/workspace`.

### Learnings

- Native Go YAML/JSON generation is practical for this repo as long as parity checks focus on rendered semantics rather than byte-for-byte file output.
- The current devcontainer merge behavior is a recursive object merge with array append semantics; reproducing that explicitly in Go is simpler and safer than trying to shell out to a JSON/YAML tool from the CLI.
- Local image refs such as `agent-sandbox-proxy:local` are useful for end-to-end CLI verification in environments without Docker pull access because they exercise the full init path while bypassing digest resolution.

### Follow-up Items

- Revisit whether the already-ported runtime commands should call into the new scaffold layer for fuller managed-file refresh behavior as part of `m13.4` lifecycle-command work.
