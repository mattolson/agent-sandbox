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

## Deprecated Docker-image fallback for agentbox

The primary supported install path is the local Go binary from GitHub Releases. The Docker CLI image remains available
as a deprecated fallback during the transition, and it has a few limitations.

**Editor integration is limited.** Commands like `agentbox edit policy` will use `vi` inside the container image rather than your host editor. Use the local binary install if you want `$EDITOR` to work normally.

**Host environment variables are not available.** Docker Compose runs inside the CLI container, so it won't see your host environment variables unless you forward them explicitly with `-e`. `HOME` is already forwarded in the recommended alias.

**File permissions.** The CLI image runs as root to avoid permission issues with the Docker socket. On Colima, file ownership is mapped automatically. On Linux, add `--user $(id -u):$(id -g)` to the `docker run` command to match your host user.

## agentbox not found after binary install

If you installed the Go binary successfully but your shell still cannot find `agentbox`, check where you installed it
and whether that directory is on your `PATH`.

- The install script defaults to `~/.local/bin`
- The manual install example also uses `~/.local/bin`
- If you install somewhere else, add that directory to your shell profile and start a new shell
- If your shell still resolves an older command path, run `hash -r` before trying again

If you previously used a shell alias that pointed `agentbox` at the retired Docker CLI image, remove that alias before
retrying the binary install.

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
  names against `docs/policy/schema.md`. Common slip: `scheme` is a singular shorthand for `schemes`; the plural
  forms are `schemes`/`methods`.
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

After editing policy, run `agentbox proxy reload` to apply the change without restarting the container.
