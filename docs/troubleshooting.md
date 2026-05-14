# Troubleshooting

## Docker credential helper errors after switching from Docker Desktop to Colima

Docker Desktop installs its own credential helper (`desktop`) in `~/.docker/config.json`. When you switch to Colima, the `docker-credential-desktop` binary is no longer on your PATH, causing errors like:

```
error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH
```

This affects any `docker pull` or `docker login` command.

**Fix:** Open `~/.docker/config.json` and change the `credsStore` value from `desktop` to `osxkeychain`:

```json
{
  "credsStore": "osxkeychain"
}
```

The `osxkeychain` helper is included with Docker CLI packages installed via Homebrew and stores credentials in macOS Keychain.

## Retired Docker-image alias for agentbox

The primary supported install path is the local Go binary from GitHub Releases. The old Docker CLI image distribution
was removed after the Go CLI cutover.

If your shell still aliases `agentbox` to `ghcr.io/mattolson/agent-sandbox-cli`, remove that alias and install the
binary from GitHub Releases. Keeping the alias can hide a working binary install and produce stale Docker pull or
editor-integration errors.

## agentbox not found after binary install

If you installed the Go binary successfully but your shell still cannot find `agentbox`, check where you installed it
and whether that directory is on your `PATH`.

- The install script defaults to `~/.local/bin`
- The manual install example also uses `~/.local/bin`
- If you install somewhere else, add that directory to your shell profile and start a new shell
- If your shell still resolves an older command path, run `hash -r` before trying again

If you previously used a shell alias that pointed `agentbox` at the retired Docker CLI image, remove that alias before
retrying the binary install.

## Proxy fails because the secret directory is missing

Agentbox mounts `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}` read-only into the proxy. Managed
compose files set `bind.create_host_path: false`, so Docker Compose fails instead of silently creating a missing
directory.

The error usually mentions that the bind source path does not exist or that the bind mount is invalid.

Create the directory on the host, keep it outside the project workspace, and retry:

```bash
mkdir -p "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
chmod 700 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
```

## Proxy fails to inject a header (missing or unreadable secret file)

A rule with `transform.request.headers` (or a GitHub `git.auth.secret`) requires the proxy to resolve the named secret at request time. If the file is missing or unreadable, the request is blocked before reaching the upstream and the proxy emits a structured rejection event:

```json
{"ts": "...", "phase": "request", "action": "blocked", "reason": "header_injection_failed", "detail": "secret_resolution_failed", "secret": "<id>"}
```

Common causes and fixes:

- **Secret file does not exist.** Create it with the same name as the secret ID under `${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}`. Use `printf '%s' "<value>" > <path>` to avoid an extra trailing newline.
- **Secret file is a symlink or non-regular file.** The resolver opens with `O_NOFOLLOW` and rejects non-regular files. Replace the symlink with the real file.
- **Secret value has embedded NUL/CR/LF or is not UTF-8.** The resolver rejects those. Rewrite the file with the literal token bytes only (one trailing newline is fine and is stripped).

See [docs/secrets.md](secrets.md) for the storage layout and ID grammar.

## Secret file has unsafe permissions

When the secret directory or a secret file is group/other readable or writable, the resolver flags it as `unsafe_permissions`. The warning rides along inside the successful `header_injection` event:

```json
{"ts": "...", "type": "header_injection", "action": "applied", "headers": [...], "warnings": [{"code": "unsafe_permissions", "path": "...", "secret": "<id>"}]}
```

Resolution still succeeds today, but tighten the mode so the warnings stop:

```bash
chmod 700 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"
chmod 600 "${AGENTBOX_SECRET_DIR:-${HOME}/.config/agent-sandbox/secrets}"/*
```

If the path is a symlink, remove the symlink and place the real file at the resolver's expected location instead.

## Credential-shim env vars not visible inside the container

Policies that use `services[].git.auth.client_shim` rely on shell env exports (`GIT_ASKPASS`, `AGENTBOX_GIT_FAKE_USERNAME`, `AGENTBOX_GIT_FAKE_PASSWORD`, `GIT_TERMINAL_PROMPT`) that are loaded at shell startup by `/etc/agent-sandbox/shell-init.sh`. Already-running processes — including the agent process you started before applying the policy — do not see updated exports.

If `git push` prompts for credentials or fails with no Authorization injection, open a new shell or restart the container:

```bash
agentbox proxy reload   # apply policy change (no container restart needed)
agentbox exec           # open a fresh shell to pick up shim env exports
```

The proxy's own header injection takes effect immediately on the next matching request; only the agent-side askpass exports need a fresh shell.

## Policy reload rejected

`agentbox proxy reload` triggers a hot reload of the proxy policy. If the rendered policy is invalid the
proxy keeps the previous policy active and logs a rejection event:

```json
{"ts": "...", "type": "reload", "action": "rejected", "error": "..."}
```

Check the proxy logs with `agentbox proxy logs` for the `error` field. Typical
causes are YAML syntax errors in a user-owned policy file and schema violations introduced in a recent edit. Fix the
source file, then re-send `SIGHUP`; a successful reload emits a matching `"action": "applied"` event.

## Policy rejected at startup with a schema error

The proxy exits immediately if the rendered policy fails validation at startup. The log line looks like:

```json
{"ts": "...", "type": "info", "msg": "<error message>"}
```

followed by the process exiting with status 1. Run `agentbox policy config` from the host to reproduce the same
render locally — the error message is identical, and the stack trace (if any) is easier to read without the
container wrapping.

Common causes and what they look like:

- **Unknown service name.** `services[N] references unknown service '<name>'; expected one of [...]`. Fix: correct
  the typo or remove the entry.
- **Unsupported key on a rule, domain, or service entry.** `... contains unsupported keys: [...]`. Fix: check key
  names against `docs/policy/schema.md`. Common slips: using `scheme` instead of `schemes`, or `method` instead of
  `methods`.
- **Non-absolute path.** `domains[N].rules[M].path.<matcher> must start with '/', got '...'`. Fix: add the leading
  slash.
- **Invalid `merge_mode`.** `...merge_mode must be 'replace' when set, got '...'`. Fix: `replace` is the only
  supported value; omit the key for default additive merge.

## Request blocked unexpectedly

When the proxy blocks a request it emits a structured decision log line through stdout. Check `agentbox proxy logs`
for a line matching the host in question. The shape is:

```json
{"ts": "...", "phase": "connect|request", "action": "blocked", "reason": "<why>", "host": "...", "scheme": "...", "matched_host": "...", "method": "...", "path": "..."}
```

The `phase` field tells you which enforcement gate ran, and `reason` names the outcome:

- `phase: connect`, `reason: host_not_allowed` — the host has no matching record. The TLS tunnel was never
  established. Fix: add the host to a `domains` entry in a user-owned policy file.
- `phase: connect`, `reason: https_not_permitted` — the host record exists but allows only `http`. Fix: add `https`
  to the rule's `schemes` list or broaden the rule.
- `phase: request`, `reason: host_not_allowed` — the host became resolvable only after request headers arrived
  (uncommon; usually means a policy reload removed the host mid-flight). Fix: re-add the host.
- `phase: request`, `reason: no_rule_matched` — the host matched, the scheme matched, but no rule allowed this
  specific method/path/query combination. Fix: relax or add a rule under the matching host.
- `phase: request`, `reason: scheme_not_permitted` — the host matched but none of its rules permit this scheme
  (usually an HTTP request to an HTTPS-only record). Fix: adjust the rule's `schemes` list.

For rules with `query.exact`, the whole normalized query-param map must match. Extra client-added params such as
pagination tokens, trace IDs, or protocol-version hints will produce `no_rule_matched`; add those params to the exact
map or remove the query constraint if they are not security-relevant.

After editing policy, run `agentbox proxy reload` to apply the change without restarting the container.
