# Go Stack

See [Language stacks](./README.md) for the shared stack workflow.

The Go stack configures these paths for the `dev` user:

- `GOPATH=$HOME/go`
- `GOBIN=$HOME/go/bin`
- `GOMODCACHE=$HOME/.cache/go-mod`
- `GOCACHE=$HOME/.cache/go-build`

For a persistent local Go dev environment, add this to `.agent-sandbox/compose/user.override.yml` to mount the tool
bin dir, module cache, build cache, and Go env:

```yaml
services:
  agent:
    volumes:
      - go-tool-bin:/home/dev/go/bin
      - go-mod-cache:/home/dev/.cache/go-mod
      - go-build-cache:/home/dev/.cache/go-build
      - go-env:/home/dev/.config/go

volumes:
  go-tool-bin:
  go-mod-cache:
  go-build-cache:
  go-env:
```

Keep source code in `/workspace`, not under `GOPATH`. The stack also installs `build-essential` and `pkg-config` so
CGO-backed packages can compile. `GOBIN` uses `$HOME/go/bin` rather than `~/.local/bin` so Go-installed tools do not
mask agent binaries such as `codex`.

For module downloads and `go install`, allow at least `proxy.golang.org` and `sum.golang.org` in your sandbox policy.
If you run the installer script inside a running sandboxed container instead of during image build, you will also need
`go.dev`.

```yaml
domains:
  - proxy.golang.org
  - sum.golang.org
```
