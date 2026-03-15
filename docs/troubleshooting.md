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

## Running agentbox CLI via Docker image

When running `agentbox` as a Docker container instead of a local install, there are a few limitations to be aware of.

**Editor integration is limited.** Commands like `agentbox edit policy` will use `vi` inside the container image rather than your host editor. Set the local install if you want `$EDITOR` to work normally.

**Host environment variables are not available.** Docker Compose runs inside the CLI container, so it won't see your host environment variables unless you forward them explicitly with `-e`. `HOME` is already forwarded in the recommended alias.

**File permissions.** The CLI image runs as root to avoid permission issues with the Docker socket. On Colima, file ownership is mapped automatically. On Linux, add `--user $(id -u):$(id -g)` to the `docker run` command to match your host user.
