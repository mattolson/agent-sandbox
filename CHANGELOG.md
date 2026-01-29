# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- **Default proxy policy now blocks all traffic.** The baked-in proxy policy no longer allows GitHub by default. You must mount a policy file to allow any outbound requests.

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

## [0.3.0] - 2026-01-25 (1a9103d)

Proxy-based network enforcement. This release replaces the iptables-only domain blocking with a two-layer architecture: mitmproxy sidecar for domain enforcement + iptables to prevent bypassing the proxy.

### Breaking Changes

- **SSH is blocked.** Port 22 is now blocked to prevent SSH tunneling that could bypass the proxy. Git must use HTTPS. The container auto-rewrites `git@github.com:` URLs to `https://github.com/`, but you may need to run `gh auth login` for push access to private repos.

- **Policy files moved to host.** Policy files must now live on the host and are mounted into the proxy container. They cannot live inside the workspace (security: prevents agent from modifying its own allowlist). The default location is `~/.config/agent-sandbox/policies/`. Copy the examples:
  ```bash
  mkdir -p ~/.config/agent-sandbox/policies
  cp docs/policy/examples/claude.yaml ~/.config/agent-sandbox/policies/claude.yaml
  cp docs/policy/examples/claude-devcontainer.yaml ~/.config/agent-sandbox/policies/claude-vscode.yaml
  ```
  You can use a different directory if you prefer, but you'll need to update the volume mount in your compose file to match.

- **Separate compose files for CLI and devcontainer.** To avoid container/volume name conflicts when running both modes:
  - CLI mode: `docker-compose.yml` (at project root)
  - Devcontainer mode: `.devcontainer/docker-compose.yml`

  If upgrading an existing project, copy the new template files from `templates/claude/`.

- **Two-container architecture.** The stack now runs two containers: `agent` and `proxy`. The proxy sidecar runs mitmproxy and enforces the domain allowlist. Update any scripts that assume a single container.

### Added

- Proxy sidecar (mitmproxy) for HTTP/HTTPS traffic logging and enforcement
- Domain allowlist enforcement at the proxy level with clear 403 error messages
- Discovery mode for observing what domains an agent needs (set `PROXY_MODE=discovery`)
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
