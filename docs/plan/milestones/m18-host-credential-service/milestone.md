# m18: Host Credential Service

Run a narrower host-side credential service for auth flows that cannot be handled cleanly by `m15-proxy-secret-injection`. The helper keeps credentials off disk inside the container, but unlike proxy injection it does allow the client to receive credential material when that is unavoidable.

## Problem

`m15-proxy-secret-injection` should be the primary path for HTTP-native credentials, especially git over HTTPS and other request-decorated auth patterns. Some flows still do not fit that model:

- Browser-driven or device-code login flows where the client expects local auth state
- Tools that insist on a credential-helper protocol instead of pure outbound request transformation
- Non-HTTP or helper-protocol-shaped credentials that the proxy cannot inject
- Current fallback patterns like `git credential-store` still write plaintext tokens where the agent can read them directly

## Goals

- Secondary credential path for cases `m15` cannot cover
- Credentials stored in the host's native credential store, never persisted on disk inside the container
- Support credential-helper-shaped clients and similar local-delivery flows
- Minimal configuration: the service starts when the sandbox starts and stops when it stops

## Design

### Architecture

```
Container                          Host
--------                          ----
client command
  -> git credential helper (shim)
    -> HTTP request to host:PORT
                                  credential-service
                                    -> git credential-osxkeychain
                                    <- username + token
    <- username + token
  -> upstream auth flow continues
```

### Components

1. **Host service** - Listens on a TCP port on the Docker bridge network. Implements a helper-facing protocol over HTTP and delegates to the host's native credential helper (`osxkeychain` on macOS, `wincred` on Windows, `libsecret` on Linux desktops).

2. **Container shim** - A small script or binary installed in the base image that acts as the client-facing helper. Translates the client protocol into HTTP calls to the host service.

3. **Network plumbing** - The host service port must be reachable from the container. The Docker bridge network is already allowed through the firewall (it's how the proxy sidecar works). The service binds to the host's Docker bridge IP on a specific port.

### Protocol

Git's credential helper protocol is still the main reference protocol for this milestone. The three operations are:

- `get` - Return credentials for a given host/protocol
- `store` - Save credentials after successful authentication
- `erase` - Remove stored credentials

The HTTP wrapper translates these into `POST /get`, `POST /store`, `POST /erase` with the key=value body. If a later client needs a different helper-facing protocol, add it only if `m15` cannot cover the use case.

### Security considerations

- The service should only accept connections from the container network, not the wider host network
- Consider scoping credential lookups to domains or services not already handled by `m15`
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

The `agentbox exec` approach is the most natural fit. The CLI already manages the compose lifecycle. It can start the credential service before `docker compose up` and stop it after `docker compose down`. This milestone should only be attempted after `m15` settles the primary proxy-based path, so the helper solves the residual set of unsupported flows instead of becoming a competing default.

## Tasks

To be broken down when work begins. Rough outline:

- Identify the residual auth flows that still cannot be handled by `m15`
- Design and implement the HTTP credential protocol wrapper
- Implement the host-side service (Go, to match the planned CLI language)
- Implement the container-side shim (shell script using curl, or a small Go binary)
- Integrate service lifecycle into `agentbox exec`
- Add the service port to the firewall allowlist
- Document setup and credential store requirements per platform
- Test with the concrete unsupported clients selected for the milestone

## Open Questions

- Should the service require an auth token of its own to prevent other containers on the same Docker network from using it?
- Which real workflows remain after `m15` lands, and are they important enough to justify the helper complexity?
- Should credential scoping (allowlist-only domains) be enforced at the service level or left to the proxy?
- Is HTTP over the Docker bridge acceptable, or should the service use a Unix socket mounted into the container?
- Should the service support credential caching (short TTL) to reduce round-trips to the host keychain?

## Definition of Done

- [ ] At least one important unsupported flow after `m15` can authenticate using the host credential service with no tokens on disk in the container
- [ ] `m15` is documented as the primary credential path and this service is documented as the fallback path
- [ ] Works on macOS (Colima) out of the box
- [ ] Documented for Windows and Linux desktop
- [ ] Graceful fallback when the service is unavailable (clear error message, not silent failure)
