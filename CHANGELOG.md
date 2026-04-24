# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

Fine-grained proxy rules from `m14`.

### Added

- **Request-aware proxy policy rules.** Policy can now constrain outbound HTTP and HTTPS traffic by `schemes`, `methods`, `path`, and exact `query` matching, while keeping host-only rules on the CONNECT fast path.
- **Semantic service catalog entries.** `services` entries can now take mapping form with options like `readonly: true`, plus GitHub-specific `repos` and `surfaces` expansion for repo-scoped API and Git smart-HTTP access.
- **Hot policy reload.** `agentbox proxy reload` now sends `SIGHUP` to the proxy, which re-renders policy in process, validates it, and atomically swaps to the new matcher while keeping the last-known-good policy on failure.
- **Request-aware policy docs and examples.** Added schema documentation, focused examples, troubleshooting guidance, and an `m14` “what’s new” note covering request rules, reload, and GitHub repo restrictions.

### Changed

- **Layered policy rendering is now rule-aware.** `render-policy` now compiles `services` and `domains` into one canonical host-record IR with deterministic same-host merge behavior and `merge_mode: replace` support.
- **Matcher normalization is tighter and more explicit.** Scheme and host matching are case-insensitive, URI-equivalent percent-encoding is canonicalized for path/query matching, and non-equivalent path/query case differences remain significant.
- **Existing domain-only policies keep working unchanged.** Plain-string `domains` and plain-string `services` still render to host-wide catch-all rules, so pre-`m14` policies retain the same effective allowlist behavior.

## [0.13.0] - 2026-04-10 (eb04cbc)

CLI rewrite from `m13`.

### Added

- **Go `agentbox` CLI implementation.** The CLI has been rewritten in Go and now covers the current user-facing command surface: `init`, `switch`, `edit compose`, `edit policy`, `policy config` / `render`, `bump`, `up`, `down`, `logs`, `compose`, `exec`, `destroy`, `version`, and shell completion.
- **Native YAML and JSON handling.** Compose, policy, and devcontainer generation now use native Go handling instead of host-side `yq`.
- **GitHub Releases binary distribution.** `agentbox` now ships as macOS and Linux binaries for `amd64` and `arm64`.
- **Draft-first Go release workflow.** Version tags now build archives plus checksums and upload them to a draft GitHub release before human publication.
- **Stable latest-download asset names.** Releases include unversioned archives like `agentbox_linux_arm64.tar.gz` plus `agentbox_checksums.txt`, so users can install the latest binary for their architecture via GitHub's `releases/latest/download/...` shortcut.
- **Install script for agentbox.** Releases now include `install.sh`, a convenience installer that detects OS and architecture, verifies checksums, and installs `agentbox` without requiring users to assemble release URLs by hand.
- **Go CLI reference.** Added `docs/cli.md` as the current command reference for `agentbox`.

### Changed

- **Go binary is now the documented install path.** README and related docs now point users to GitHub Releases binaries instead of the old Bash checkout flow.
- **Generated YAML now uses two-space indentation consistently.** Native scaffold writers and template checks now align Go-generated YAML with the repository templates.
- **Codex image now includes `bubblewrap`.** Codex's Linux startup probe finds `/usr/bin/bwrap` without warning, while isolation remains handled by the surrounding container, proxy, and firewall.
- **Repository tooling is Go-only.** Build scripts, CI, contributor docs, and repo guidance now assume the Go CLI implementation and embedded templates as the only live source of truth.

### Removed

- **Legacy Bash CLI implementation.** The old `cli/` tree, parity harness, shell-based test workflow, and transition-only template-sync plumbing have been removed now that the Go CLI is the only supported implementation.
- **Docker-based CLI image distribution.** `agent-sandbox-cli` is no longer built or documented as an install path.

## [0.12.0] - 2026-03-28 (01b39fe)

OpenCode agent support from `m12`.

### Added

- **OpenCode agent support.** Added the `agent-sandbox-opencode` image, layered CLI and devcontainer templates, CLI agent registry integration, and end-user docs for running OpenCode through the standard `agentbox` workflow.
- **OpenCode proxy and CI wiring.** Added OpenCode service support in the proxy, image build support in `images/build.sh`, GitHub Actions image publishing, and daily version checks for new OpenCode releases.
- **Provider-agnostic OpenCode documentation.** Documented provider policy setup for Anthropic, OpenAI, Google, and similar backends, plus the sandbox-specific env vars that disable auto-update and LSP downloads.

## [0.11.0] - 2026-03-25 (fc29431)

Pi agent support from `m11`.

### Added

- **Pi agent support.** Added the `agent-sandbox-pi` image, layered CLI and devcontainer templates, CLI agent registry integration, and end-user docs for running Pi through the standard `agentbox` workflow.
- **Pi proxy and CI wiring.** Added Pi support in the proxy agent registry, image build support in `images/build.sh`, GitHub Actions image publishing, and daily version checks for new Pi releases.
- **Provider-agnostic Pi documentation.** Documented provider policy setup, API-key and OAuth-based authentication flows, and the optional npm allowlist needed for `pi install` and `pi update`.

## [0.10.0] - 2026-03-22 (32b5d2d)

Factory agent support from `m10`.

### Added

- **Factory agent support.** Added the `agent-sandbox-factory` image, layered CLI and devcontainer templates, CLI agent registry integration, and end-user docs for running Factory through the standard `agentbox` workflow.
- **Factory proxy and CI wiring.** Added Factory service domains in the proxy, image build support in `images/build.sh`, GitHub Actions image publishing, and daily version checks for new Factory CLI releases.
- **Factory auth and usage documentation.** Documented the OAuth-based login flow and the CLI's auto-approve usage mode inside the sandbox.

## [0.9.0] - 2026-03-15 (549b2d5)

Gemini agent support from `m9`.

### Added

- **Gemini agent support.** Added the `agent-sandbox-gemini` image, layered CLI and devcontainer templates, CLI agent registry integration, and end-user docs for running Gemini through the standard `agentbox` workflow.
- **Gemini proxy and CI wiring.** Added Gemini service domains in the proxy, image build support in `images/build.sh`, GitHub Actions image publishing, and daily version checks for new Gemini CLI releases.
- **Gemini IDE companion support.** Added VS Code devcontainer integration for the Gemini IDE companion extension while documenting JetBrains as unsupported.

## [0.8.0] - 2026-03-14 (f422f7a)

Agent switching without data loss, plus a new layered runtime model from `m8`.

### Added

- **`agentbox switch --agent <name>`.** Switch between supported agents without reinitializing the project. `switch` updates the active agent, lazily scaffolds missing agent runtime files, refreshes `.devcontainer/devcontainer.json` for devcontainer projects, and preserves per-agent state volumes so credentials/history survive switching back.

- **Layered compose ownership.** Managed runtime files now live under `.agent-sandbox/compose/` as:
  - `base.yml`
  - `agent.<agent>.yml`
  - `mode.devcontainer.yml`

  User customizations now live in user-owned files that agentbox does not overwrite:
  - `.agent-sandbox/compose/user.override.yml`
  - `.agent-sandbox/compose/user.agent.<agent>.override.yml`

- **Layered policy ownership and runtime merge.** Policy customizations now live under `.agent-sandbox/policy/` as shared and agent-specific user-owned files. The proxy renders the effective policy at startup from the managed active-agent baseline plus:
  - `.agent-sandbox/policy/user.policy.yaml`
  - `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`
  - `.agent-sandbox/policy/policy.devcontainer.yaml` for devcontainer workflows

- **Effective policy inspection.** `agentbox policy config` / `agentbox policy render` now show the same merged policy that proxy runtime enforcement uses.

- **Dedicated upgrade guide for legacy layouts.** Added `docs/upgrades/m8-layered-layout.md` with the rename-and-rerun upgrade flow for pre-`m8` projects.

### Changed

- **Devcontainer projects now use a thin IDE shim.** `.devcontainer/` is now reduced to `devcontainer.json` plus optional `devcontainer.user.json`. Managed compose and policy runtime files moved into `.agent-sandbox/`, so CLI and devcontainer workflows share one runtime ownership model.

- **Compose and policy commands now target layered user-owned surfaces.** `agentbox edit compose` edits the shared `.agent-sandbox/compose/user.override.yml`. `agentbox edit policy` edits layered shared or agent-specific policy files instead of standalone per-mode generated files.

- **Switching a running stack reconciles the runtime immediately.** When containers are already running, `agentbox switch` brings the old stack down and starts the selected agent's stack back up so the visible runtime matches the new active agent.

### Breaking Changes

- **Pre-`m8` single-file layouts are no longer supported by current commands.** Commands such as `init`, `switch`, runtime compose commands, `edit compose`, `edit policy`, and `bump` now fail fast when they detect legacy files such as:
  - `.agent-sandbox/docker-compose.yml`
  - `.devcontainer/docker-compose.yml`
  - `.agent-sandbox/policy-cli-<agent>.yaml`

  Upgrade requires following the guide in `docs/upgrades/m8-layered-layout.md`: rename the old generated files, rerun `agentbox init`, then copy customizations into the new layered user-owned files.

## [0.6.0] - 2026-02-22 (141b04d)

The `agentbox` CLI. A single command-line tool for the full sandbox lifecycle: init, exec, edit, bump, destroy.

### Added

- **`agentbox` CLI.** New command-line tool for initializing and managing sandboxed projects. Commands:
  - `agentbox init` - set up a project with agent, mode, and IDE selection; accepts `--agent`, `--mode`, `--ide`, `--name`, `--path` flags for non-interactive usage; optional volume mounts included as commented-out entries
  - `agentbox exec` - start or attach to the agent container
  - `agentbox edit policy` - open the network policy in your editor, auto-restarts proxy on save
  - `agentbox edit compose` - open the compose file in your editor
  - `agentbox bump` - pull latest images and pin to new digests
  - `agentbox <command>` - pass-through to `docker compose` with the correct project file
  - `agentbox destroy` - remove containers, volumes, and config directories
  - `agentbox version` - show version info

- **Docker-based CLI distribution.** Run the CLI without a local install:
  ```bash
  docker pull ghcr.io/mattolson/agent-sandbox-cli
  alias agentbox='docker run --rm -it -v "/var/run/docker.sock:/var/run/docker.sock" -v"$PWD:$PWD" -w"$PWD" -e TERM -e HOME --network none ghcr.io/mattolson/agent-sandbox-cli'
  ```

- **Image pinning during init.** `agentbox init` pulls images and pins them to their digest in the generated compose file for reproducibility.

- **Bash 3.2 compatibility.** The CLI works with the default Bash shipped on macOS.

### Changed

- **Policy files generated per-project.** `agentbox init` creates the policy at `.agent-sandbox/policy-<mode>-<agent>.yaml` inside your project. This replaces the previous approach of copying policy examples to `~/.config/agent-sandbox/policies/`.

## [0.5.0] - 2026-02-08 (37be5a3)

Deep customization. Dotfiles, shell-init hooks, and language stacks without forking Dockerfiles.

### Added

- **Dotfiles auto-linking.** Mount `~/.config/agent-sandbox/dotfiles` and files are recursively symlinked into `$HOME` at container startup. Protected paths (`.config/agent-sandbox`) are skipped.

- **System-level shell initialization.** Shell-init hooks now run from `/etc/zsh/zshrc` (system-level) before `~/.zshrc`. Drop scripts in `~/.config/agent-sandbox/shell.d/*.sh` on the host. They survive custom `.zshrc` replacements via dotfiles.

- **Language stack installer scripts.** Scripts for python, node, go, and rust shipped at `/etc/agent-sandbox/stacks/` in the base image. Each handles multi-arch (amd64/arm64) and accepts an optional version argument.

- **`STACKS` build arg.** One-liner stack installation when building custom images: `STACKS="python,go:1.23" ./images/build.sh base`.

- **`EXTRA_PACKAGES` build arg.** Extend the base image with additional apt packages at build time, validated against an allowlist.

### Changed

- **Simplified base image.** Removed optional packages to reduce image size and build time:
  - `yq` (YAML processor)
  - `git-delta` (diff viewer)
  - `zsh-in-docker` / powerline10k theme

  The base image now ships with a minimal zsh configuration. To add these tools or customize further, create a derived image:

  ```dockerfile
  FROM ghcr.io/mattolson/agent-sandbox-base:latest

  # Install git-delta
  RUN ARCH=$(dpkg --print-architecture) && \
    wget "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
    dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
    rm "git-delta_0.18.2_${ARCH}.deb"

  # Or mount your own dotfiles for shell customization
  ```

## [0.4.0] - 2026-02-04 (c778f0f)

Multi-agent support. Claude Code and GitHub Copilot, with JetBrains IDE integration.

### Added

- **GitHub Copilot agent support.** New `agent-sandbox-copilot` image and templates for running GitHub Copilot CLI in a sandbox.

- **JetBrains IDE support.** Devcontainer mode supports JetBrains IDEs with appropriate capabilities and plugin configuration.

### Changed

- **Default proxy policy now blocks all traffic.** The baked-in proxy policy no longer allows GitHub by default. You must mount a policy file to allow any outbound requests.

## [0.3.0] - 2026-01-25 (1a9103d)

Proxy-based network enforcement. This release replaces the iptables-only domain blocking with a two-layer architecture: mitmproxy sidecar for domain enforcement + iptables to prevent bypassing the proxy.

### Breaking Changes

- **SSH is blocked.** Port 22 is now blocked to prevent SSH tunneling that could bypass the proxy. Git must use HTTPS. The container auto-rewrites `git@github.com:` URLs to `https://github.com/`, but you may need to run `gh auth login` for push access to private repos.

- **Policy files managed by CLI.** Policy files are generated by `agentbox init` and stored in your project at `.agent-sandbox/policy-<mode>-<agent>.yaml`. They are mounted read-only into the proxy container. The agent cannot modify its own allowlist.

- **Separate compose files for CLI and devcontainer.** To avoid container/volume name conflicts when running both modes:
  - CLI mode: `.agent-sandbox/docker-compose.yml`
  - Devcontainer mode: `.devcontainer/docker-compose.yml`

  Use `agentbox init` to generate the appropriate configuration.

- **Two-container architecture.** The stack now runs two containers: `agent` and `proxy`. The proxy sidecar runs mitmproxy and enforces the domain allowlist. Update any scripts that assume a single container.

### Added

- Proxy sidecar (mitmproxy) for HTTP/HTTPS traffic logging and enforcement
- Domain allowlist enforcement at the proxy level with clear 403 error messages
- Log mode for observing what domains an agent needs (set `PROXY_MODE=log`)
- Structured JSON logging of all proxied requests
- `gh` CLI pre-installed for GitHub operations
- Auto-rewrite of git SSH URLs to HTTPS

### Changed

- Firewall now blocks all direct outbound except to Docker bridge network (forces traffic through proxy)
- Policy changes take effect on proxy restart (`docker compose restart proxy`) instead of container rebuild

### Removed

- Direct domain-based iptables rules (replaced by proxy enforcement)
- SSH (port 22) access

## [0.2.5] - 2025-01-22 (835c541)

### Added

- Shell customization via `~/.config/agent-sandbox/shell.d/` mount
- Support for dotfiles directory mounting
- Read-only mounts to prevent agent modification of host config

## [0.2.0] - 2025-01-19 (725d9be)

### Added

- Multi-platform images (amd64 + arm64) published to GitHub Container Registry
- GitHub Actions workflow for automated builds
- Image digest pinning for reproducibility

## [0.1.0] - 2025-01-17 (98ad81d)

Initial release.

### Added

- Base image with Debian bookworm, zsh, powerline10k
- Claude Code agent image
- Policy YAML format for domain allowlists
- Devcontainer template (`templates/claude/`)
- Iptables-based network lockdown
- Documentation for Colima + Docker setup
