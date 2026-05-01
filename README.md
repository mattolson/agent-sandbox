# Agent Sandbox

> [!WARNING]
> This project is still in early-stage development. You can expect breaking changes between releases.

Run AI coding agents in a locked-down local sandbox with:

- Minimal filesystem access (read/write access to only the repository directory)
- Configurable egress policy enforced by sidecar proxy (hosts plus optional scheme, method, path, and query rules)
- Iptables firewall preventing direct outbound (all traffic must go through the proxy)
- Reproducible environments (Debian container with pinned dependencies)
- Persistent volume for agent state - auth and config preserved across container restarts
- Ability to easily switch between agents without losing state
- Support for CLI and devcontainers (including VS Code and JetBrains IDEs)

Target platform: [Colima](https://github.com/abiosoft/colima) + [Docker Engine](https://docs.docker.com/engine/) on Apple Silicon. Should work with any Docker-compatible runtime.

## Runtime modes

**CLI (preferred)** - run the agent in a terminal session using `agentbox exec`.

**Devcontainer** - open the project in VS Code or JetBrains and let the IDE manage the container lifecycle.

## Supported agents

| Agent | CLI | VS Code | JetBrains |
|-------|-----|---------|-----------|
| [Claude Code](https://code.claude.com/docs/en/overview) | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| [Codex](https://github.com/openai/codex) | :white_check_mark: | :heavy_check_mark: | :heavy_check_mark: |
| [Gemini](https://github.com/google-gemini/gemini-cli) | :heavy_check_mark: | :heavy_check_mark: | :no_entry_sign: |
| [OpenCode](https://github.com/anomalyco/opencode) | :heavy_check_mark: | :heavy_check_mark: | :no_entry_sign: |
| [Pi](https://github.com/badlogic/pi-mono) | :heavy_check_mark: | :no_entry_sign: | :no_entry_sign: |
| [Factory](https://docs.factory.ai/cli) | :heavy_check_mark: | :heavy_check_mark: | :heavy_check_mark: |
| [Copilot](https://github.com/github/copilot-cli) | :heavy_check_mark: | :heavy_check_mark: | :no_entry_sign: |

* :white_check_mark: **Full Support** - stable, heavily used by maintainers
* :heavy_check_mark: **Preview** - tested during initial integration, but not heavily used by maintainers. Contributions, documentation, and bug reports welcome.
* :no_entry_sign: **Not Supported** - known blockers
  * Copilot's IntelliJ plugin [cannot complete auth in a devcontainer](https://github.com/microsoft/copilot-intellij-feedback/issues/1375).
  * No official Google Gemini plugin available for JetBrains
  * No JetBrains extension available for OpenCode
  * No IDE extensions available for Pi

## Quick start (macOS + Colima)

### 1. Install prerequisites

You need a VM and Docker (along with docker-compose and docker-buildx) installed. This can be done in a variety of ways.

* [Colima](https://colima.run/)
* [Podman](https://podman.io/)
* [OrbStack](https://orbstack.dev/)
* [Docker Desktop](https://www.docker.com/products/docker-desktop/)
* [Rancher Desktop](https://rancherdesktop.io/)

Instructions that follow are for Colima.

```bash
# colima for virtual machine
# docker for the core docker engine
# docker-compose for agentbox runtime
# docker-buildx for building images locally
brew install colima docker docker-compose docker-buildx

# Start the virtual machine
colima start --edit
```

### 2. Install agent-sandbox CLI

Download the `agentbox` binary from [GitHub Releases](https://github.com/mattolson/agent-sandbox/releases).

#### Quick install

```bash
curl -fsSL https://github.com/mattolson/agent-sandbox/releases/latest/download/install.sh | sh
```

The installer defaults to `~/.local/bin`. To choose a version or install directory:

```bash
curl -fsSL https://github.com/mattolson/agent-sandbox/releases/latest/download/install.sh | \
  sh -s -- --version v0.13.0 --install-dir /usr/local/bin
```

#### Manual install

```bash
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

ASSET="agentbox_${OS}_${ARCH}.tar.gz"

cd /tmp
curl -fsSLO \
  "https://github.com/mattolson/agent-sandbox/releases/latest/download/${ASSET}"
tar -xzf "${ASSET}"
mkdir -p "${HOME}/.local/bin"
install -m 755 "/tmp/agentbox_${OS}_${ARCH}/agentbox" "${HOME}/.local/bin/agentbox"
"${HOME}/.local/bin/agentbox" version
```

If you want to verify the archive before installing it, download `agentbox_checksums.txt` from the same release and
compare the checksum for `${ASSET}` against `shasum -a 256 "${ASSET}"` on macOS or `sha256sum "${ASSET}"` on Linux.

If you want a pinned install instead of "latest", use the versioned assets attached to a specific release tag such as
`agentbox_<version>_<os>_<arch>.tar.gz` together with `agentbox_<version>_checksums.txt`.

If `~/.local/bin` is not already on your `PATH`, add it in your shell profile before running `agentbox` directly.

### 3. Initialize the sandbox for your project

```bash
agentbox init
```

This prompts interactively for the project name, agent, mode, and IDE when needed, then generates the docker compose and network policy files for the sandbox.

See the [CLI reference](docs/cli.md) for the full list of commands, flags, and environment variables.

To inspect the configuration after init, use `agentbox policy config` to output the effective network policy and
`agentbox compose config` for the fully combined docker compose stack.

### 4. Start the sandbox

**CLI:**

```bash
# Open a shell in the agent container
agentbox exec

# Then, inside the container, start your agent cli (e.g. claude).
# Because you're in a sandbox, you can even try yolo mode!
claude --dangerously-skip-permissions
```

**Devcontainer (VS Code / JetBrains):**

VS Code:
1. Install the Dev Containers extension
2. Command Palette > "Dev Containers: Reopen in Container"

JetBrains (IntelliJ, PyCharm, WebStorm, etc.):
1. Open your project
2. From the Remote Development menu, select "Dev Containers"
3. Select the devcontainer configuration

### 5. Agent-specific setup

Follow the setup instructions specific to the agent image you are using:
- [Claude Code](docs/agents/claude.md)
- [Codex](docs/agents/codex.md)
- [Gemini](docs/agents/gemini.md)
- [OpenCode](docs/agents/opencode.md)
- [Pi](docs/agents/pi.md)
- [Factory](docs/agents/factory.md)
- [Copilot](docs/agents/copilot.md)

## Switching agents

Switch to a different agent without reinitializing the project:

```bash
agentbox switch --agent codex
```

`switch` preserves user-owned override files and per-agent state volumes (credentials, history). In devcontainer projects it regenerates `.devcontainer/devcontainer.json` for the selected agent.

## Network policy

Network enforcement has two layers:

1. **Proxy** (mitmproxy sidecar) - Enforces allowed hosts plus optional request-aware rules. Blocks non-matching traffic with 403.
2. **Firewall** (iptables) - Blocks all direct outbound from the agent container. Only the Docker host network is reachable, which is where the proxy sidecar runs. This prevents applications from bypassing the proxy.

The proxy image ships with a default policy that blocks all traffic. `agentbox init` sets up the layered policy files and active-agent baseline for your project.

### How it works

The agent container has `HTTP_PROXY`/`HTTPS_PROXY` set to point at the proxy sidecar. The proxy runs a mitmproxy addon (`enforcer.py`) that checks HTTPS CONNECT tunnels against the host policy, then checks decrypted HTTP/HTTPS requests against any scheme, method, path, or query rules. Non-matching requests get a 403 response.

The agent's iptables firewall (`init-firewall.sh`) blocks all direct outbound except to the Docker bridge network. This means even if an application ignores the proxy env vars, it cannot reach the internet directly.

The proxy's CA certificate is shared via a Docker volume and automatically installed into the agent's system trust store at startup.

### Customizing the policy

The network policy lives in your project in the `.agent-sandbox/policy/` directory.

To edit the policy file:

```bash
agentbox edit policy
```

This opens the user layer file (`.agent-sandbox/policy/user.policy.yaml`) in your editor, which will be preserved across agent switches, and will be applied on top of the base agent policy. If you save active-policy changes while the proxy is running, `agentbox` hot-reloads the proxy policy.

Example policy:

```yaml
services:
  - github

domains:
  - registry.npmjs.org
  - host: api.example.com
    rules:
      - schemes: [https]
        methods: [GET]
        path:
          prefix: /v1/public/
```

Public package registries such as PyPI are intentionally not allowed by default. If you need them, add them explicitly
to your user or per-agent policy. Prefer a private mirror or proxy when you have one.

GitHub can also be narrowed by repository:

```yaml
services:
  - name: github
    merge_mode: replace
    readonly: true
    repos:
      - owner/repo
    surfaces: [api, git]
```

If you edit policy files directly, apply changes without restarting the proxy:

```bash
agentbox proxy reload
agentbox proxy logs
```

If you want to make customizations that apply to a single agent, you can edit the file `.agent-sandbox/policy/user.agent.<agent>.policy.yaml`. For example, to add a host or request rule only when using Claude Code, add it to the file `user.agent.claude.policy.yaml`.

See [docs/policy/schema.md](./docs/policy/schema.md) for the full policy format reference and [docs/upgrades/m14-request-aware-rules.md](./docs/upgrades/m14-request-aware-rules.md) for a tour of request-aware rules.

## Customization

- **[Git inside the container](docs/git.md)** - Credential setup and SSH-to-HTTPS rewriting
- **[Dotfiles and shell customization](docs/dotfiles.md)** - Mount dotfiles and shell.d scripts
- **[Language stacks](docs/stacks/)** - Extend the base image with Python, Node, Go, Rust and stack-specific guides
- **[Image versioning](docs/images.md)** - Pin and bump image digests
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and fixes

## Security

This project reduces risk but does not eliminate it. Local dev is inherently best-effort sandboxing.

Key principles:

- Minimal mounts: only the repo workspace + project-scoped agent state
- Network egress is tightly controlled through sidecar proxy with default deny policy
- Firewall verification runs at every container start

### Git credentials

If you store git credentials inside the container (via `git credential-store` or any other method), the token grants access to whatever repositories it was scoped to. A classic personal access token or OAuth token grants access to **all repositories** your GitHub account can access, not just the current project. The network policy limits which hosts and URL shapes traffic can use, but it does not inspect request headers or bodies. An agent with a broad token could still read or modify any repository reachable through an allowed GitHub endpoint.

For defense in depth, and to limit exposure:

- **Run git from the host** - No credentials in the container at all
- **Use a fine-grained PAT** - Scope the token to specific repositories
- **Use a separate GitHub account** - Isolate sandboxed work entirely

### IDE devcontainer

Operating as a devcontainer (VS Code or JetBrains) opens a management channel between the IDE and the container. This channel is separate from the agent's normal network data plane.

What this means in practice:

- The proxy and iptables firewall still constrain ordinary outbound traffic from processes in the container
- IDE-managed features such as port forwarding, localhost callbacks, opening browser URLs on the host, and extension RPC are part of a separate control plane
- Blocking the container's bridge-network traffic does not fully remove that IDE control plane
- Installing IDE extensions can [introduce additional risk](https://blog.theredguild.org/leveraging-vscode-internals-to-escape-containers/)

Treat the IDE and its extensions as trusted host-side code. If you want the tightest boundary, use CLI mode instead of devcontainer mode.

### Security issues

See [SECURITY.md](./SECURITY.md) for the reporting process. Do not post full reproduction details for sandbox escapes, proxy or firewall bypasses, credential exposure, or similar security issues in a public issue.

## Roadmap

See [docs/roadmap.md](./docs/roadmap.md) for planned features and milestones.

## Troubleshooting

Running into problems? Check the [troubleshooting guide](docs/troubleshooting.md).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution paths, issue labels, planning requirements, and PR expectations.

## License

[MIT License](./LICENSE)
