# Image Versioning

The `agentbox init` command automatically pulls the latest images and pins the compose file to sha digests for reproducibility.

To update to newer image versions later:

```bash
agentbox bump
```

This pulls the newest versions and updates the compose file with the new sha digests.

To use locally-built images instead:

```bash
./images/build.sh
agentbox edit compose
# Update the images to use:
#   agent service: agent-sandbox-claude:local
#   proxy service: agent-sandbox-proxy:local
```

## Local Dev Image

This applies to developing agent-sandbox itself, not to using it.

`agentbox bump` only repins digests in the managed compose layers. If a user
override pins the agent service to a locally built image, those digests are
never pulled at run time and `bump` alone changes nothing you can see. This repo
is in exactly that position: `.agent-sandbox/compose/user.agent.<agent>.override.yml`
points the agent service at `agent-sandbox-dev:<agent>`, built by `make setup`.

`make setup` alone does not pick up a new agent release either. `images/build.sh`
defaults every agent version to `latest`, which is a cache-stable build arg, so
Docker reuses the cached install layer and the agent CLI is never reinstalled.

Use `make bump` to update the dev image:

```bash
make bump
```

It runs `agentbox bump`, reads the agent CLI version label off each newly pinned
image, records the versions in `scripts/dev-image-versions.env`, and then runs
`make setup`. The concrete version busts the Docker cache, so the installer
actually reruns. Then recreate the container with `agentbox up -d`.

Run `make bump` from the host. It needs Docker, which sandboxed agents cannot
reach.

`make bump` fails, without touching the pins, when it cannot read a concrete
version for the agent it is about to build. That happens when the pull failed,
the image was built from `latest`, or the version label is missing. Otherwise
`make setup` would rebuild the dev image at a stale pin while reporting success.

To build one agent at a specific version without touching the pins:

```bash
CLAUDE_CODE_VERSION=2.1.261 make setup
```

An explicit environment variable always wins over `scripts/dev-image-versions.env`.

Hermes is pinned by its calver git tag in `HERMES_VERSION`. `make bump` also
records the release's semver as `HERMES_SEMVER` so the local image carries the
same `hermes-version` label as the published one. An explicit `HERMES_VERSION`
ignores the pinned semver, and the image is labelled with the tag instead.
