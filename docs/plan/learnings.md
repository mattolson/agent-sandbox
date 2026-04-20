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
