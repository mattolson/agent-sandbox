# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Draft-first Go binary release flow.** Version tags now build macOS and Linux `agentbox` archives plus checksums and upload them to a draft GitHub release before human publication.
- **Stable latest-download asset names.** Releases now include unversioned archives like `agentbox_linux_arm64.tar.gz` plus `agentbox_checksums.txt`, so users can install the latest binary for their architecture via GitHub's `releases/latest/download/...` shortcut.

### Changed

- **Go binary is now the primary documented install path.** README and CLI docs now point users to GitHub Releases binaries instead of telling them to clone `cli/bin`.
- **Documented host-side `yq` requirement removed from the primary install flow.** The Go binary handles YAML and JSON natively, so users no longer need `brew install yq` just to install `agentbox`.
- **Docker CLI image is now documented as a deprecated fallback.** The image remains available during the transition, but it is no longer presented as the primary way to install the CLI.

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
