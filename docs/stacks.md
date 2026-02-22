# Language Stacks

The base image ships installer scripts for common language stacks. Extend the agent image with a custom Dockerfile:

```dockerfile
FROM ghcr.io/mattolson/agent-sandbox-claude:latest
USER root
RUN /etc/agent-sandbox/stacks/python.sh
RUN /etc/agent-sandbox/stacks/go.sh 1.23.6
USER dev
```

Build and use your custom image:
```bash
docker build -t my-custom-sandbox .
agentbox edit compose
# Update the agent service image to: my-custom-sandbox
```

Available stacks:

| Stack | Script | Version arg | Default |
|-------|--------|-------------|---------|
| Python | `python.sh` | (ignored, uses apt) | System Python 3 |
| Node.js | `node.sh` | Major version | 22 |
| Go | `go.sh` | Full version | 1.23.6 |
| Rust | `rust.sh` | Toolchain | stable |

Each script handles both amd64 and arm64 architectures.

Alternatively, if building from source, use the `STACKS` env var:

```bash
STACKS="python,go:1.23.6" ./images/build.sh all
```
