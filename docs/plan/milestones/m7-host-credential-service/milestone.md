# m7: Host Credential Service

Run a lightweight credential helper service on the host that bridges the container to the host's native credential store (macOS Keychain, Windows Credential Manager, etc.). No secrets are stored inside the container.

## Problem

Git credential setup inside the container is either insecure or cumbersome:

- `git credential-store` writes plaintext tokens to `~/.git-credentials`
- `gh auth login` silently falls back to plaintext `~/.config/gh/hosts.yml` because there is no D-Bus/keyring in the container
- Both approaches leave tokens on disk where the agent can read them directly
- Users on macOS expect credentials to live in Keychain, encrypted at rest

## Goals

- Credentials stored in the host's native credential store, never on disk inside the container
- Works with any program that supports git's credential helper protocol (git, gh, etc.)
- The agent can use credentials through the protocol but cannot read raw tokens
- Minimal configuration: the service starts when the sandbox starts and stops when it stops

## Design

### Architecture

```
Container                          Host
--------                          ----
git push
  -> git credential helper (shim)
    -> HTTP request to host:PORT
                                  credential-service
                                    -> git credential-osxkeychain
                                    <- username + token
    <- username + token
  -> HTTPS push to github.com
```

### Components

1. **Host service** - Listens on a TCP port on the Docker bridge network. Implements the git credential helper protocol (`get`, `store`, `erase`) over HTTP. Delegates to the host's native credential helper (`osxkeychain` on macOS, `wincred` on Windows, `libsecret` on Linux desktops).

2. **Container shim** - A small script or binary installed in the base image that acts as a git credential helper. Translates git's stdin/stdout credential protocol into HTTP calls to the host service.

3. **Network plumbing** - The host service port must be reachable from the container. The Docker bridge network is already allowed through the firewall (it's how the proxy sidecar works). The service binds to the host's Docker bridge IP on a specific port.

### Protocol

Git's credential helper protocol is line-based key=value pairs over stdin/stdout. The three operations:

- `get` - Return credentials for a given host/protocol
- `store` - Save credentials after successful authentication
- `erase` - Remove stored credentials

The HTTP wrapper translates these into `POST /get`, `POST /store`, `POST /erase` with the key=value body.

### Security considerations

- The service should only accept connections from the container network, not the wider host network
- Consider scoping credential lookups to domains on the proxy allowlist (prevents the agent from probing for credentials to arbitrary hosts)
- The raw token transits the Docker bridge network in the HTTP response. This is the same trust boundary as the proxy CA cert distribution, which already happens over this path
- Rate limiting or audit logging on the host service would help detect credential abuse

### Platform support

| Platform | Backend |
|---|---|
| macOS | `git credential-osxkeychain` (Keychain) |
| Windows | `git credential-manager` (Windows Credential Manager) |
| Linux desktop | `git credential-libsecret` (gnome-keyring / KWallet) |
| Linux headless | Falls back to `git credential-store` on the host (still better than in-container plaintext since the agent can't read the host filesystem) |

## Integration

The service could run as:
- A sidecar container in the compose stack (simplest, but needs host credential store access)
- A host-side process started by `agentbox exec` (more natural, direct access to host keychain)
- Part of the proxy sidecar (reuses existing infrastructure, but mixes concerns)

The `agentbox exec` approach is the most natural fit. The CLI already manages the compose lifecycle. It can start the credential service before `docker compose up` and stop it after `docker compose down`.

## Tasks

To be broken down when work begins. Rough outline:

- Design and implement the HTTP credential protocol wrapper
- Implement the host-side service (Go, to match the planned CLI language)
- Implement the container-side shim (shell script using curl, or a small Go binary)
- Integrate service lifecycle into `agentbox exec`
- Add the service port to the firewall allowlist
- Document setup and credential store requirements per platform
- Test with git push/pull, gh CLI, and other credential-aware tools

## Open Questions

- Should the service require an auth token of its own to prevent other containers on the same Docker network from using it?
- Should credential scoping (allowlist-only domains) be enforced at the service level or left to the proxy?
- Is HTTP over the Docker bridge acceptable, or should the service use a Unix socket mounted into the container?
- Should the service support credential caching (short TTL) to reduce round-trips to the host keychain?

## Definition of Done

- [ ] `git push` from inside the container authenticates using host Keychain with no tokens on disk in the container
- [ ] `git credential-store` and `gh auth login` are no longer the recommended credential setup
- [ ] Works on macOS (Colima) out of the box
- [ ] Documented for Windows and Linux desktop
- [ ] Graceful fallback when the service is unavailable (clear error message, not silent failure)
