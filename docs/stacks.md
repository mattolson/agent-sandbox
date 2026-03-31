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

The Go stack configures these paths for the `dev` user:

- `GOPATH=$HOME/go`
- `GOBIN=$HOME/.local/bin`
- `GOMODCACHE=$HOME/.cache/go-mod`
- `GOCACHE=$HOME/.cache/go-build`

For a persistent local Go dev environment, add this to
`.agent-sandbox/compose/user.override.yml` to mount the tool bin dir, module
cache, build cache, and Go env:

```yaml
services:
  agent:
    volumes:
      - go-bin:/home/dev/.local/bin
      - go-mod-cache:/home/dev/.cache/go-mod
      - go-build-cache:/home/dev/.cache/go-build
      - go-env:/home/dev/.config/go

volumes:
  go-bin:
  go-mod-cache:
  go-build-cache:
  go-env:
```

Keep source code in `/workspace`, not under `GOPATH`. The stack also installs
`build-essential` and `pkg-config` so CGO-backed packages can compile.

For module downloads and `go install`, allow at least `proxy.golang.org` and
`sum.golang.org` in your sandbox policy. If you run the installer script inside
a running sandboxed container instead of during image build, you will also need
`go.dev`.

```yaml
domains:
  - proxy.golang.org
  - sum.golang.org
```

Available stacks:

| Stack | Script | Version arg | Default |
|-------|--------|-------------|---------|
| Python | `python.sh` | (ignored, uses apt) | System Python 3 |
| Node.js | `node.sh` | Major version | 22 |
| Go | `go.sh` | Full version | 1.26.1 |
| Rust | `rust.sh` | Toolchain | stable |

Each script handles both amd64 and arm64 architectures.

Advanced: if you are rebuilding this repo's images from source, you can also use the `STACKS` env var during image
builds. This applies to the base image, so rebuild downstream agent images too:

```bash
STACKS="python,go:1.26.1" ./images/build.sh all
```
