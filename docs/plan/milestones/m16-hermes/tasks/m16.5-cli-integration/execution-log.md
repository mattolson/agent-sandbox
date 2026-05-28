# Execution Log: m16.5 - Hermes CLI Agent Registry Entry

## 2026-05-27 - Registry add complete, host-side init smoke deferred

**Code changes:**

- `internal/runtime/agents.go`: appended `"hermes"` to `supportedAgents`.
- `internal/runtime/agents_test.go`: appended `,hermes` to the expected order string in `TestSupportedAgentsOrder`.

**Issue surfaced during test run:** the plan called for two edits but missed two more places that hardcode the agent
list in expected error-message strings:

- `internal/cli/init_test.go:TestInitRejectsInvalidAgentValue` — expected error text included the full agent list.
- `internal/cli/switch_test.go` — same shape (`"Invalid agent: invalid (expected: ...)"`).

Both updated to include `hermes` in the expected list. Easy to miss because they live in tests for *invalid* agent
cases, not valid-agent flows, so the agent-list grep I ran initially didn't surface them as obviously.

**Learning:** when adding to a list rendered into a user-facing error message, grep for the *current* list-as-string
form (e.g., `"claude codex gemini"` or `"claude,codex,gemini"`) not just for individual agent names. Hardcoded
expected-error tests are a recurring blind spot for list extensions.

**Tests:** `go test ./...` passes after the four edits. `go vet ./...` clean.

**Help text verification:** built binary with `go build ./cmd/agentbox`. Both `agentbox init --help` and
`agentbox switch --help` show:

```
--agent string   Agent to configure (claude codex gemini opencode pi copilot factory hermes)
```

**End-to-end init smoke not feasible from this sandbox.** Tried
`agentbox init --batch --name hermes-smoke --agent hermes --mode cli --path /tmp/hermes-init-XXXXXX` against a temp
directory. The init flow calls `docker.ResolvePinnedImage` which fails with:

```
Failed to pull 'ghcr.io/mattolson/agent-sandbox-proxy:latest' and no local copy exists.
```

The agent container has no docker CLI and ghcr.io isn't in the proxy allowlist. There's no `--image` or
`--no-pull` flag on `init` to bypass this. Three options were considered:

1. Run the smoke on host (where Docker exists and `agent-sandbox-proxy:local` is built locally). The proxy image
   resolution would still likely fail because it looks for `:latest`, not `:local`, but worth a try if you want.
2. Bypass image resolution with a flag. None exists; adding one is out of scope for m16.5.
3. **Skip the init smoke entirely.** The unit tests cover the agent-validation paths; the templates exist and load
   via embed FS (`TestReadTemplateLoadsHermesAgentTemplate`); the help-text check above confirms the registry
   wiring. End-to-end manual verification happens in m16.7 anyway, running on host with the local image stack
   actually built.

Going with option 3. Acceptance criteria adjusted: the init-smoke item is marked deferred-to-m16.7 rather than
blocking m16.5.

**Status:** task complete pending commit. Four files changed (two source, two test).

## 2026-05-27 - Plan drafted

Smallest task in the milestone. Two one-line edits.

**Survey of agent-list consumers across the codebase** confirmed that only two files have hardcoded knowledge of the
agent list:

- `internal/runtime/agents.go` defines `supportedAgents`. Single source of truth.
- `internal/runtime/agents_test.go:TestSupportedAgentsOrder` does an exact-string assertion on the joined slice. Must
  be updated in lockstep.

Every other CLI surface (`switch.go`, `edit.go`, `init.go`, `bump.go`, `lifecycle.go`, `legacy.go`) and helper
(`SupportedAgentsDisplay`, `ValidateAgent`) consumes the list via `SupportedAgents()`. They pick up hermes for free.

**Ordering decision:** existing list `claude,codex,gemini,opencode,pi,copilot,factory` is not strictly alphabetical;
it looks like "alphabetical-ish batches appended as new agents land." Newest agent goes at the end. Hermes joins as
`..., factory, hermes`.

**Smoke verification plan:** build the binary, eyeball `--help` output for `init` and `switch`, then exercise
`agentbox init --agent hermes --mode cli` against a temp directory. The init step requires Docker image resolution
(pinned digests via `docker.ResolvePinnedImage`), which may fail in this sandbox because the agent image is only
local (`agent-sandbox-hermes:local`, not yet published to ghcr). If that becomes a hangup during execution, defer the
end-to-end init smoke to host-side (where the local image exists) or pass an explicit `--image` flag, or skip the
smoke entirely and rely on the unit tests plus the broader m16.7 manual verification.

Awaiting approval to execute.
