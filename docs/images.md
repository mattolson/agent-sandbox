# Image Versioning

The `agentbox init` command automatically pulls the latest images and pins the compose file to sha digests for reproducibility.

To update to newer image versions later:

```bash
agentbox compose bump
```

This pulls the newest versions and updates the compose file with the new sha digests.

To use locally-built images instead:

```bash
./images/build.sh
agentbox compose edit
# Update the images to use:
#   agent service: agent-sandbox-claude:local
#   proxy service: agent-sandbox-proxy:local
```
