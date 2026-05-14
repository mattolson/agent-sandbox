# Secrets

The proxy can inject credentials into outbound requests at the policy layer.
This page describes where those credentials live on the host, how to add and
update them, and what the boundary does and does not promise.

The authoring shapes that reference secrets — `services[].git.auth.secret`,
`services[].git.auth.client_shim`, and `domains[].transform.request` — are
documented in [docs/policy/schema.md](policy/schema.md). This page is the
runtime side: storage layout, freshness, and non-goals.

## Storage layout

Agentbox mounts a single host directory into the proxy container, read-only:

| Side  | Path                                                              |
|-------|-------------------------------------------------------------------|
| Host  | `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}`   |
| Proxy | `/run/secrets/agentbox` (default `AGENTBOX_SECRET_SOURCE` target) |

One file per secret. The file name is the secret ID referenced from policy.
The file contents are the raw secret value with at most one trailing newline.

The directory is mounted with `bind.create_host_path: false`, so Docker
Compose fails fast instead of silently creating it. Create it yourself before
`agentbox up`:

```bash
mkdir -p "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
chmod 700 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
```

The directory must not be inside the project workspace — the agent container
must not be able to read or replace its own secrets.

## Permissions

The resolver expects:

- Directory mode `0700`. Group or other read/write permissions emit a
  `unsafe_permissions` warning.
- Each secret file mode `0600`. Same warning surface for unsafe modes.
- Each secret file is a regular file. Symlinks and other non-regular file
  types are rejected outright; the resolver `lstat`s the path, opens with
  `O_NOFOLLOW`, and re-checks the type after open.

Unsafe permissions do not block resolution today, but they are logged as a
structured warning on every matching request. The recommended way to silence
them is to tighten the mode, not to ignore the warning.

## Secret IDs

Secret IDs follow `[A-Za-z0-9._-]+`. The ID is the file name verbatim, with no
parent directories: the resolver rejects any ID that does not map to a direct
child of the secret root.

Recommended naming convention: dotted segments that name the service, project
scope, and intended use. For example:

- `github.agent-sandbox.push-token`
- `github.agent-sandbox.read-token`
- `internal.api-token`

The convention is purely organizational. The resolver only enforces the
character set and the direct-child constraint.

## Adding a secret

Write the value directly with `printf` to avoid the trailing newline that
`echo` adds:

```bash
printf '%s' "ghp_examplevalue" \
  > "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.agent-sandbox.push-token"
chmod 600 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}/github.agent-sandbox.push-token"
```

A single trailing `\n` or `\r\n` is stripped on read; embedded NUL, CR, or LF
bytes are rejected. The file must contain valid UTF-8.

There is no `agentbox secrets` CLI in this milestone. Manual provisioning is
the only supported path.

## Freshness and reload

The file backend reads each secret on demand at request time. When a secret
file changes:

- The next matching request sees the new value without a proxy reload.
- Already in-flight requests keep the value they already resolved.

`agentbox proxy reload` is for **policy** changes, not secret changes. A
secret rotation in place needs no `SIGHUP`.

The `client_shim` env exports are a separate concern. Those values come from
the rendered policy, not from the secret file, and they are loaded on shell
startup (`/etc/agent-sandbox/shell-init.sh`). Already-running agent processes
do not see updates to those exports until they are restarted. Open a new
shell or restart the container after a policy reload that changes a shim.

## Scope

The file backend is global today: one secret directory per host, no project
or target overlay. The internal `SecretResolutionContext` carries `project`
and `target` fields so a future task can add overlays without changing the
authored policy shape. Until that lands, the same secret ID resolves to the
same file regardless of which project or agent target is making the request.

## Future direction: Keychain backend

`AGENTBOX_SECRET_SOURCE` is a URL: `file:/run/secrets/agentbox` is the only
scheme today. A future task can add a `keychain:...` backend that resolves
the same logical secret IDs against macOS Keychain. The policy and reference
shapes (`secret: github.agent-sandbox.push-token`) do not change.

## Non-goals

The proxy's credential injection feature does not:

- Scan request bodies, response bodies, or arbitrary URLs for leaked secret
  values. Header injection is the entire surface.
- Detect or block secrets that an agent encodes into the path, query string,
  or body. If your policy lets an agent talk to a host, that host can receive
  whatever the agent puts on the wire.
- Block a separate credential helper (`git credential-store`, browser
  session cookies, environment variables) that the agent configures inside
  the container. The proxy only acts on rules in the rendered policy.
- Replace fine-grained scoping. A leaked secret with broad scope is still
  broad; the proxy can only constrain which hosts and URL shapes it travels
  with, not what it grants on the upstream side.

For the security boundary as a whole, see the
[Security section in README.md](../README.md#security).
