# Language Stacks

The base image ships installer scripts for common language stacks. The recommended approach is to extend your current
agent image with a custom Dockerfile. For reproducibility, prefer the pinned image currently referenced by your
project's `.agent-sandbox/compose/agent.<agent>.yml` instead of `:latest`.

```dockerfile
FROM ghcr.io/mattolson/agent-sandbox-opencode@sha256:<current-digest>
USER root
RUN /etc/agent-sandbox/stacks/python.sh
RUN /etc/agent-sandbox/stacks/go.sh 1.26.1
USER dev
```

Build and use your custom image:

```bash
docker build -f Dockerfile.dev -t my-custom-sandbox .
agentbox edit compose
# Update the agent service image to: my-custom-sandbox
agentbox up -d
```

## Available Stacks

| Stack | Script | Version arg | Default | Guide |
|-------|--------|-------------|---------|-------|
| Python | `python.sh` | (ignored, uses apt) | System Python 3 | - |
| Node.js | `node.sh` | Major version | 22 | - |
| Go | `go.sh` | Full version | 1.26.1 | [Go stack](./go.md) |
| Rust | `rust.sh` | Toolchain | stable | - |

Each script handles both amd64 and arm64 architectures.

## Stack-Specific Guides

- [Go stack](./go.md) - Go environment variables, persistent local dev mounts, and policy requirements

## Advanced

If you are rebuilding this repo's images from source, you can also use the `STACKS` env var during image builds. This
applies to the base image, so rebuild downstream agent images too:

```bash
STACKS="python,go:1.26.1" ./images/build.sh all
```
