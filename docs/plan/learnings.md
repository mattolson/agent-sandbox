# Learnings

Lessons learned during project execution. Review at the start of each planning session.

## Technical

- iptables rules must preserve Docker's internal DNS resolution (127.0.0.11 NAT rules) or container DNS breaks
- `aggregate` tool is useful for collapsing GitHub's many IP ranges into fewer CIDR blocks
- VS Code devcontainers need `--cap-add=NET_ADMIN` and `--cap-add=NET_RAW` for iptables to work
- Policy schema should nest by concern (`egress:`, future `ingress:`, `mounts:`) for extensibility
- `yq` will be needed to parse YAML in the firewall script
- VS Code devcontainers bypass Docker ENTRYPOINT; use `postStartCommand` for runtime initialization that must run every container start
- Entrypoint scripts should be idempotent (check for existing state before acting) to support both devcontainer and compose workflows
- devcontainer.json and docker-compose.yml need separate volume/mount configs; they serve different workflows and VS Code reads devcontainer.json directly
- yq syntax `.foo // [] | .[]` safely iterates arrays that may be missing or null
- Shell-sourced state files should write user-facing values with shell escaping (`%q`) or later reads can break on spaces and special characters
- Policy files that control security must live outside the workspace and be mounted read-only; otherwise the agent can modify them and re-run initialization to bypass restrictions
- Baking default policies into images is safe (agent can't modify the image) and provides good UX (works out of the box)
- Policy layering via Dockerfile COPY overwrites parent layer's policy cleanly
- Sudoers with specific script paths (not commands) restricts what users can escalate to; agent can sudo init-firewall.sh but not iptables directly
- Debian's default sudoers includes `env_reset`, which clears user environment variables; POLICY_FILE set by user won't pass through sudo
- HTTP_PROXY/HTTPS_PROXY env vars are opt-in; applications can ignore them and connect directly
- mitmproxy can read SNI (Server Name Indication) from TLS ClientHello without MITM decryption, enabling hostname logging for HTTPS
- Transparent proxy (iptables REDIRECT) works for same-container proxy but is complex for cross-container (requires TPROXY or custom routing)
- SSH allows tunneling (-D, -L, -R) which can bypass other network restrictions; blocking SSH entirely is simpler than trying to restrict it
- Shared shell helpers that use `mapfile` must source `compat.bash` or macOS Bash 3.2 support regresses silently
- `runtime/debug.ReadBuildInfo` exposes VCS revision, timestamp, and dirty state for local Go builds in a checkout, so early Go CLIs can print useful version metadata without depending on a generated `.version` file
- Shell-escaped state files written with Bash `%q` can be parsed safely in Go with a shell-style splitter instead of sourcing them
- `go version -m` is a practical way to validate embedded build metadata in cross-compiled Go release binaries without having to execute every target artifact on the current host
- Stable `releases/latest/download/...` URLs require stable artifact names and stable archive contents; an unversioned filename is not enough if the tarball still unpacks into a versioned directory
- Keeping the live template source of truth inside the shipped Go codebase is simpler than synchronizing from a legacy tree that exists only for transition compatibility
- mitmproxy `Request.path` can include the query string, so request-aware proxy matching should split path and query explicitly instead of assuming the framework already separated them
- A renderer-side service catalog that emits canonical host-record fragments keeps service semantics out of the matcher; the matcher stays generic and every new rich service compiles into the same IR the authored `domains` already use
- Service-level `merge_mode: replace` works cleanly when the renderer tracks which rule identities a service contributed per host; replacement then becomes a targeted drop of those identities instead of a full host-level override
- GitHub `git` readonly semantics belong inside the catalog, not the matcher: readonly expands to the `git-upload-pack` clone/fetch pair and readwrite adds the matching `git-receive-pack` pair, so the authored `readonly` flag stays generic while the protocol-specific expansion stays local to the GitHub service
- Canonical catalog output should not be re-normalized inside the renderer; re-running host/rule normalization is wasteful defensive code and blurs the "catalog emits IR, renderer merges IR" boundary
- `/opt/proxy-python/bin/python3` is the canonical interpreter for proxy test runs; system Python lacks the `yaml` module that `render-policy` depends on
- mitmproxy reserves SIGINT and SIGTERM for shutdown but leaves SIGHUP unclaimed; addons can install their own SIGHUP handler through `loop.add_signal_handler` in the `running()` hook and remove it in `done()` without interfering with shutdown
- `asyncio.Event.set()` is not safe to call from a worker thread — use `threading.Event` on both sides and bridge to the loop with `loop.run_in_executor(None, event.wait)` when the loop needs to wait on a thread's signal
- For signal-driven reloads on a rare, manual trigger, prefer `asyncio.ensure_future(reload())` + `asyncio.Lock` inside `reload()` over a "drop duplicate in-flight signal" guard: the guard loses the latest on-disk edit when signals burst, while lock-serialized reloads drain in milliseconds and guarantee latest-wins semantics
- Thick unit coverage does not substitute for integration wiring coverage. Unit tests that inject a renderer callable (`reload_renderer=...`) miss SystemExit + stderr-printing behavior of the real CLI-style renderer; integration tests that drive real `mitmdump` uncover it immediately
- `except Exception` does not catch `SystemExit` — a renderer that uses `sys.exit(1)` after printing to stderr will crash reload silently; wrap the production renderer in `contextlib.redirect_stderr` + explicit `except SystemExit` so the real error message flows into the structured rejection event
- urllib's `ProxyHandler` honors `no_proxy` / `proxy_bypass()` even when explicitly configured, so loopback targets silently bypass the proxy; integration tests that must exercise the proxy need a raw-socket HTTP client using absolute-form request URIs
- The initial-load path (`PolicyMatcher.from_policy_path`) is stricter than the renderer: it requires `query.exact.<name>` to be a list, while `render-policy` accepts a bare string and promotes it. Policy files that serve both paths must use the matcher's stricter form
- Shared proxy helper modules used by both `render-policy` and addons must account for the image layout: renderer helpers live under `/usr/local/lib/agent-sandbox/proxy`, while addons run from `/home/mitmproxy/addons`
- Rule-scoped policy metadata should be attached before host-record merge and dedupe so the existing full-rule identity preserves scope without creating host-wide side effects
- File-backed secret readers should validate with `lstat()`, open with `O_NOFOLLOW` when available, and verify with
  `fstat()` after opening so symlink and non-regular-file rejection remains true during the actual read
- Docker Compose service volume handling should preserve both short-form strings and long-syntax mappings; security
  options such as `bind.create_host_path: false` require long syntax, while named volumes are still simplest as strings
- Compose `--no-interpolate` preserves authored variable expressions but can produce misleading normalized paths for
  nested default expressions; validate generated YAML separately from runtime semantic `compose config` checks
- Proxy rules with request transforms must force request inspection at CONNECT time for HTTPS, even if the rule has no
  method/path/query constraints; otherwise the proxy can allow a tunnel before it sees headers to mutate
- Request-time header injection should stage all rendered header values before mutating the flow, so a later secret
  resolution or transform failure blocks without leaving a partially mutated request
- When a renderer helper gains a new shared-module dependency, import-path tests should copy and isolate that dependency
  too; otherwise tests can accidentally pass by reusing a module already loaded from the repo path
- Keep internal catalog field names distinct from rejected author-facing policy fields so test failures and future
  refactors do not blur unsupported syntax with canonical intermediate representation
- Shared named-volume mount targets should be pre-created with compatible ownership in every image that may initialize
  the volume. Startup order is useful, but it should not be the only thing making a shared runtime file writable.
- Agent-visible credential shim metadata should remain renderer- and catalog-owned, not arbitrary author-facing
  environment surfaces, so fake credential setup stays coupled to the proxy replacement rules that make it safe.
- mitmproxy forwards requests to the host named in the URL it receives, so integration tests against catalog rules
  that hard-code real hostnames (e.g. `github.com`) must rebind the rendered host onto loopback rather than relying
  on DNS or matcher tricks; rebinding preserves the catalog's rule shape under test while isolating the proxy from
  the real internet.
- `SourceFileLoader.load_module()` is deprecated in modern Python; prefer
  `spec_from_loader` + `module_from_spec` + `exec_module` when loading non-`.py` scripts such as `render-policy` so
  test runs stay free of DeprecationWarnings.
- The proxy's GitHub repo matcher is case-sensitive on `owner/repo`, on both the `repos:` policy entry AND the
  request path. `repos: [NousResearch/hermes-agent]` does not match a `git clone` request that uses lowercase, and
  vice versa, even though GitHub serves both cases as the same repo. Workaround: lowercase the policy entry AND use
  a lowercase clone URL. Durable fix: case-fold owner/repo on both sides of the match in the catalog. m14 follow-up.
- For an agent with runtime self-modification behavior (lazy installs, plugin auto-install, on-demand model registry
  fetches), the sandbox needs **both** env-var defaults AND a baked config file that disables those behaviors. Env
  vars alone do not catch a config-driven knob, and an unsandboxed lazy-install path turns the container into a
  moving target. Surface this during discovery for every new agent and bake the disable into the image, not just
  into the compose env.
- For agent-discovery work that must read upstream source, prefer a local clone (`git clone --depth 1` into `/tmp`)
  over WebFetch. WebFetch summarizes content even when asked for verbatim text, which is lossy for grep-style
  extraction of env var names, hardcoded URLs, and exact config-key strings. Pin the clone to a commit SHA in the
  discovery output so findings remain interpretable when downstream tasks execute later.
- One-shot `docker run --rm <agent-image> <cmd>` hangs or fails on any image extending `agent-sandbox-base` because
  the base entrypoint runs firewall init (requires NET_ADMIN + a proxy sidecar). For build-time validation, put the
  check inside a `RUN` step in the Dockerfile (it runs without the entrypoint). For runtime probes that don't need
  the full sandbox stack, pass `--entrypoint ""` to unset the entrypoint and pass the command as the CMD. Full
  sandbox runs happen via `agentbox exec` which brings up the compose stack and proxy.
- When extending a list (agents, modes, IDEs) that gets rendered into a user-facing error message, grep for the
  joined-list string form (e.g., `"claude codex gemini opencode pi copilot factory"`) — not just individual
  list-member names. Tests for the *invalid* case assert against the literal error string and are easy to miss
  with a name-only grep. Patterns to grep: `"expected: <first>"` and `"<first>,<second>"`.
- Match upstream agent-Dockerfile conventions for `ARG <AGENT>_VERSION` defaults: use `latest` as the sentinel and
  put any install-source-specific handling (e.g., conditional `==${VERSION}` vs unpinned install for pip,
  `releases/latest` vs `releases/download/<v>` URL for binaries) in the RUN block. Deviating by pinning a specific
  version as the ARG default creates a hidden interaction with `build.sh`'s default of `<AGENT>_VERSION=latest` —
  the bug only surfaces when build.sh and the Dockerfile are exercised together via `./images/build.sh <agent>`.
- `build.sh`'s pre-target case (line ~43) and main case (line ~225) are two separate places that list known agent
  targets. Both must be updated when adding a new agent — the pre-target case decides whether `$1` is recognized
  vs. falling through to the `all` default. Missing the pre-target case makes `./build.sh <newagent>` silently
  build everything instead of just the new agent.

## Architecture

- Devcontainer value diminishes when not using VS Code integrated terminal; compose-first may be cleaner for the core runtime
- "Baked default + optional override" pattern works well for security-sensitive config: ship sensible defaults in the image, allow power users to mount custom config from host (read-only, outside workspace)
- For sandboxing, separate enforcement from the sandboxed process: sidecar containers can't be killed/modified by the agent
- iptables as gatekeeper + proxy as enforcer is more robust than either alone: iptables ensures traffic goes through proxy, proxy does domain-level filtering
- Defense in depth works when layers serve different purposes; redundant enforcement at the same layer adds complexity without security benefit
- Devcontainers can use Docker Compose backend via `dockerComposeFile` in devcontainer.json, enabling sidecar patterns
- Relative paths in docker-compose files are resolved from the compose file's directory, not the project root; `.devcontainer/docker-compose.yml` needs `../` to reach repo root, not `../../`
- Devcontainer-specific policy rules should be additive layers on top of the shared `.agent-sandbox` policy files, not a second standalone source of truth
- When legacy layouts need a cleanup-compatible exception, put guardrails in user-facing entrypoints instead of deleting every low-level fallback helper
- A reusable runtime-layout resolver plus an injectable Docker runner makes CLI parity testing practical without a live Docker daemon for every command-path test
- The current `devcontainer.user.json` merge behavior is a recursive object merge with array-append semantics, so native Go replacements need explicit tests for extension/plugin lists instead of assuming overwrite semantics
- Local image refs such as `:local` or short local names are useful for end-to-end CLI verification in restricted environments because they bypass pull-and-pin network work while still exercising the full command path
- For proxy addons that can block requests before a response hook runs, storing the policy decision on the flow avoids later response logging from accidentally relabeling blocked requests as allowed

## Security

- Threat model matters: sandboxing AI agents is about preventing unexpected network calls, not defending against actively malicious code trying to evade detection
- Privilege separation: run setup scripts as root, then drop to non-root user; non-root user can't modify iptables even if they can run specific sudo scripts
- Co-locating monitoring with the monitored process is weaker than external monitoring; process can kill/modify local monitors
- Environment variable-based proxy configuration is advisory, not enforced; must combine with network-level enforcement
- Allowing SSH to arbitrary hosts is equivalent to allowing arbitrary network access (tunneling)
- The Docker host network (172.x.0.0/24) being open to the agent is acceptable when other containers on that network are explicitly configured sidecars

## Process

- VS Code integrated terminal adds trailing whitespace on copy, making copied commands unusable; iTerm + docker exec is the workaround
- Documentation artifacts (schema docs, examples) belong in `docs/`, not in task execution directories
- Default edit commands should keep pointing at shared cross-mode config unless the user explicitly asks for a mode-specific override
- For user-facing runtime config, one clear ownership directory is better than a "cleaner" split across `.agent-sandbox/` and `.devcontainer/`; keep `.devcontainer/` as a thin IDE shim when possible
- Keep CLI stderr concise for large migrations; point users at a dedicated upgrade guide instead of trying to explain the whole layout change inline
- Regression tests over `docker compose config --no-interpolate` should assert semantic invariants, not one YAML shape; env and volume nodes vary across Compose and `yq` versions
- If runtime sync can recreate missing compose layers, resolve the compose file list after sync instead of before it or Docker will run with a stale stack that omits the freshly restored files
- Native scaffold refresh helpers can safely power lifecycle commands as long as they only rewrite agentbox-managed layers and never overwrite user-owned override or policy files during sync
- Bash `edit` flows are not fully batch-friendly because `open_editor` binds stdio to `/dev/tty`; parity automation needs a pseudo-tty when exercising the real Bash path
- Bash edit commands use second-resolution mtimes for change detection, so parity fixtures need a deliberate delay before writing file changes or real edits may be misclassified as unchanged
- Draft-first binary release workflows are safer than publishing first and attaching assets later because they avoid public releases with missing or partial artifacts while keeping the tag as the build source of truth
- Once the cutover is complete, keeping the legacy implementation around quickly turns into duplicated docs, workflows, and asset pipelines rather than meaningful safety
- User-facing docs that quote structured log shapes (JSON event examples in troubleshooting guides) should be verified against the actual emit sites in code, not paraphrased from memory or from a related test. Users grep proxy logs for the literal strings the doc shows; a fabricated `"type": "secret_warning"` field that does not exist in the enforcer is worse than no example
- Renderer-owned IR fields (`credential_shim` today) need user docs that explain both halves: "rejected when authored at the top level of a source policy file" and "expected in the rendered output when an opt-in service entry asks for it". Documenting only the rejection makes the rendered shape look like a leak; documenting only the rendered shape invites users to author it directly
- Driving user-facing example files from existing integration test scenarios (`test_github_git_injection.py`, `test_credential_shim_replace.py`, `test_proxy_enforcement.py::test_header_injection_reaches_upstream_for_matched_rule`) gives the example a permanent canary: if the renderer or catalog shifts, an integration test breaks at the same time the example would become wrong. Examples decoupled from tests drift silently
- For a multi-doc reference rewrite, keep one canonical doc (here, `docs/policy/schema.md`) and have every other doc link back to it for grammars and supported values. Re-deriving the secret ID grammar in `docs/secrets.md`, `docs/git.md`, and `docs/troubleshooting.md` would create three places that go stale independently
- A schema-doc correction for an unreleased feature is not a migration. `docs/upgrades/` should be reserved for genuine breaking changes against released behavior; cleaning up an unshipped syntax variant (the `surfaces` / repo-scoped `readonly` paragraphs) is just a doc fix
