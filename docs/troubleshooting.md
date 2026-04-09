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

- `sudo install ... /usr/local/bin/agentbox` works on most macOS and Linux setups because `/usr/local/bin` is already on `PATH`
- If you install somewhere else, add that directory to your shell profile and start a new shell
- If your shell still resolves an older command path, run `hash -r` before trying again
