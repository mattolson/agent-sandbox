# m7-codex

**Status: Not started**

Add OpenAI Codex CLI as a supported agent.

## Goal

A user can run `agentbox init --agent codex` and get a working sandbox with Codex CLI installed, its internal sandbox disabled (we control sandboxing at the container level), and the proxy configured for OpenAI API domains.

## Scope

**Included:**
- Codex agent Docker image (binary install from GitHub releases, no Node.js)
- CLI and devcontainer compose templates
- devcontainer.json template
- Proxy service domain entry for OpenAI endpoints
- CLI init integration (codex as selectable agent)
- Build script updates
- CI workflows (build job + daily version check)
- Agent documentation

**Excluded:**
- Host config mounting (no equivalent of Claude's CLAUDE.md pattern needed yet)
- Codex VS Code extension support (Codex is CLI-only as of Feb 2026)
- Fine-grained proxy rules for OpenAI API paths (m14)

## Applicable Learnings

- "Baked default + optional override" pattern: ship a default `config.toml` in the image with `sandbox_mode = "danger-full-access"` to disable Codex's internal Landlock/seccomp sandbox. Users can override via host mount if needed.
- Separate images per agent: extend base with only what Codex needs. No Node.js runtime required since the Rust binary is self-contained.
- Policy files outside workspace, mounted read-only: same pattern as Claude and Copilot.
- HTTP/2 disabled for Go programs: the `GODEBUG=http2client=0` workaround for `gh` CLI still applies in the Codex compose template.

## Design Decisions

### Binary install over npm

Codex CLI was rewritten in Rust and ships as a statically-linked musl binary. The npm package (`@openai/codex`) is just a distribution wrapper. Installing via npm would require Node.js in the image (like Copilot), but the direct binary download avoids that dependency entirely. Smaller image, fewer moving parts.

The Dockerfile will download the appropriate binary from GitHub releases based on `TARGETARCH`. Release assets follow the naming pattern:
- `codex-x86_64-unknown-linux-musl.tar.gz` (amd64)
- `codex-aarch64-unknown-linux-musl.tar.gz` (arm64)

### Disable Codex internal sandbox

Codex uses Landlock + seccomp on Linux to sandbox the commands it spawns. Inside our container (iptables + proxy + restricted filesystem), this second sandbox layer adds confusion without security benefit. Competing sandbox systems can cause cryptic permission errors.

Disable via `sandbox_mode = "danger-full-access"` in a default `config.toml` baked into the image at `~/.codex/config.toml`. This is the approach [recommended by OpenAI](https://developers.openai.com/codex/security/) for Docker/container environments.

### Both API key and device code OAuth supported

Codex supports two auth methods:
1. **API key** (`OPENAI_API_KEY` env var) - straightforward, always works
2. **Device code OAuth** (`codex login --device-auth`) - displays a URL and code to enter on any browser, no localhost callback needed. Must be [enabled in ChatGPT workspace settings](https://github.com/openai/codex/issues/9253) by an admin.

The proxy domain allowlist includes both OpenAI API domains and OAuth domains (`auth.openai.com`, `chatgpt.com`, `console.openai.com`) so either auth method works out of the box.

## Tasks

### m7.1-dockerfile

**Summary:** Create the Codex agent Docker image with binary install from GitHub releases.

**Scope:**
- Dockerfile at `images/agents/codex/Dockerfile` extending `agent-sandbox-base`
- Multi-arch support via `TARGETARCH` (map to release asset names)
- Download and install Codex binary from GitHub releases
- `CODEX_VERSION` build arg (default: `latest`)
- Create `~/.codex/` config directory
- Bake default `config.toml` with `sandbox_mode = "danger-full-access"`
- Standard OCI labels

**Acceptance Criteria:**
- Image builds for both amd64 and arm64
- `codex --version` works inside the container
- Codex's internal sandbox is disabled by default
- No Node.js installed in the image

**Dependencies:** None

**Risks:**
- GitHub release asset naming could change between versions. Pin to a known-good version for initial testing, then parameterize.
- The `config.toml` format could change. Keep the baked config minimal (only sandbox_mode).

### m7.2-proxy-domains

**Summary:** Add OpenAI service domains to the proxy enforcer.

**Scope:**
- Add `codex` service entry to `SERVICE_DOMAINS` in `images/proxy/addons/enforcer.py`
- API domains: `api.openai.com`, `*.openai.com` (covers subdomains like `us.api.openai.com`)
- OAuth domains: `auth.openai.com`, `chatgpt.com`, `*.chatgpt.com`, `console.openai.com`

**Acceptance Criteria:**
- `services: [codex]` in a policy file allows traffic to OpenAI API and OAuth endpoints
- Requests to unlisted domains are still blocked

**Dependencies:** None

**Risks:** None significant. Same pattern as existing services.

### m7.3-templates

**Summary:** Create CLI and devcontainer compose templates and devcontainer.json for Codex.

**Scope:**
- `cli/templates/codex/cli/docker-compose.yml`
- `cli/templates/codex/devcontainer/docker-compose.yml`
- `cli/templates/codex/devcontainer/devcontainer.json`
- Named volumes: `codex-state` (for `~/.codex/`), `codex-history` (shell history)
- Environment: `CODEX_HOME=/home/dev/.codex`, proxy settings, `GODEBUG=http2client=0`
- No agent-specific VS Code extension (Codex is CLI-only)
- devcontainer.json name: "Codex CLI Sandbox"

**Acceptance Criteria:**
- Templates render correctly via `agentbox init --agent codex --mode cli` and `--mode devcontainer`
- Compose files reference the correct image and volume names
- Proxy settings route traffic through the sidecar

**Dependencies:** m7.1 (image must exist for correct image reference)

**Risks:** None significant. Follows established template pattern.

### m7.4-cli-integration

**Summary:** Wire Codex into the CLI init flow and build script.

**Scope:**
- Add `codex` to `available_agents` array in `cli/libexec/init/init`
- Add `CODEX_VERSION` variable and `build_codex()` function to `images/build.sh`
- Add `codex` to the `all` build target
- Update build.sh usage documentation
- No changes needed to `cli/lib/composefile.bash` (no agent-specific host config mounting)

**Acceptance Criteria:**
- `agentbox init` shows codex as an option in interactive mode
- `agentbox init --agent codex` works in non-interactive mode
- `./images/build.sh codex` builds the image
- `./images/build.sh all` includes codex

**Dependencies:** m7.1 (Dockerfile), m7.3 (templates)

**Risks:** None significant.

### m7.5-ci-workflows

**Summary:** Add GitHub Actions build job and daily version check for Codex.

**Scope:**
- Add `CODEX_IMAGE_NAME` env var to `build-images.yml`
- Add `build-codex` job following the Claude/Copilot pattern
- Version detection: query GitHub releases API (`gh api repos/openai/codex/releases/latest`), strip `rust-v` prefix from tag name. This matches our install source directly (no npm intermediary). The `/releases/latest` endpoint skips pre-releases by default.
- Add to summary job
- Create `.github/workflows/check-codex-version.yml` (daily cron at 8am UTC, offset from Claude at 6am and Copilot at 7am)

**Acceptance Criteria:**
- Push to main builds and publishes codex image to GHCR
- Daily cron detects new Codex releases and triggers rebuild
- Image tagged with `latest`, `sha-<commit>`, and `codex-X.Y.Z`

**Dependencies:** m7.1 (Dockerfile must exist for build to succeed)

**Risks:**
- GitHub release tag format (`rust-v{VERSION}`) could change. The `sed` strip is simple enough to adjust if it does.

### m7.6-docs-and-testing

**Summary:** Document Codex agent support and verify the full workflow.

**Scope:**
- Create `docs/codex/README.md` with setup instructions, auth (API key and device code OAuth), and known limitations
- Update project README agent list
- Manual test: `agentbox init --agent codex --mode cli`, start containers, verify Codex can reach OpenAI API through proxy, verify blocked domains are rejected

**Acceptance Criteria:**
- Documentation covers init, auth setup, and running Codex in the sandbox
- End-to-end workflow works: init, exec, codex command runs, API calls go through proxy

**Dependencies:** m7.1 through m7.5

**Risks:** None significant.

## Execution Order

1. **m7.1** and **m7.2** in parallel (no dependencies between them)
2. **m7.3** after m7.1 (templates reference the image)
3. **m7.4** after m7.1 and m7.3 (CLI needs Dockerfile and templates)
4. **m7.5** after m7.1 (CI needs Dockerfile)
5. **m7.6** after all others (integration testing)

```
m7.1-dockerfile ──┬──> m7.3-templates ──> m7.4-cli-integration ──> m7.6-docs-and-testing
                  │                                                        ^
                  └──> m7.5-ci-workflows ──────────────────────────────────┘
m7.2-proxy-domains (parallel with everything except m7.6)
```

In practice, m7.1 through m7.4 could be a single PR since the changes are small and tightly coupled. m7.5 (CI) is naturally a separate PR. m7.6 spans verification of everything.

## Risks

- **GitHub release asset naming instability:** Codex is actively developed and the release artifact naming convention could change. Mitigate by pinning to a known version for the initial implementation and testing the download in CI.
- **Codex sandbox conflicts:** Even with `danger-full-access`, Codex may still attempt sandbox setup and log warnings. Acceptable as long as it doesn't block execution. Test early.
- **GitHub release tag format change:** The `rust-v` prefix convention could change. Low risk since it's been stable across 70+ releases, and the fix is a one-line `sed` update.

## Definition of Done

- [ ] `agentbox init --agent codex` works for both CLI and devcontainer modes
- [ ] Codex image builds for amd64 and arm64 with no Node.js dependency
- [ ] Codex's internal sandbox is disabled in the container
- [ ] Proxy allows traffic to OpenAI API and OAuth domains, blocks everything else
- [ ] `./images/build.sh codex` and `./images/build.sh all` succeed
- [ ] CI builds and publishes image on push to main
- [ ] Daily version check detects new Codex releases
- [ ] Documentation covers setup, auth, and usage
