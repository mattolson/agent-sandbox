# m6: Deep Customization

Extend the customization story from m2.5 to support dotfiles, custom zshrc, and language stacks without forking Dockerfiles.

## Goals

- Shell-init hooks survive user .zshrc replacement (system-level sourcing)
- First-class dotfiles support with recursive auto-symlinking at startup
- Language stack installer scripts shipped in base image (python, node, go, rust)
- STACKS build arg for one-liner stack installation via build.sh

## Design

### Image layer model

```
Layer 1: Base image       (OS, tools, firewall, shell hooks)
Layer 2: Language stacks  (optional, via feature scripts)
Layer 3: Agent            (Claude Code, Copilot, etc.)
Layer 4: Project-specific (user's Dockerfile extends agent image)
```

Layers 2 and 4 are optional. Published images cover layers 1 and 3. Users who need stacks build locally or extend the published image with a short Dockerfile.

### Shell initialization (after changes)

```
/etc/zsh/zshenv             -> sources /etc/zsh/zshenv.d/*.zsh (PATH from stacks)
/etc/zsh/zshrc              -> sources /etc/agent-sandbox/shell-init.sh
  shell-init.sh             -> sources shell.d/*.sh
~/.zshrc                    -> user's config (image default or mounted dotfile)
```

### Dotfiles auto-linking

When `~/.dotfiles` is mounted, `link-dotfiles.sh` runs at container startup:

- Recursively finds regular files in `~/.dotfiles/`
- Creates symlinks at corresponding `$HOME` paths
- Creates intermediate directories as needed (mkdir -p)
- Skips protected prefixes: `.config/agent-sandbox`
- Silently ignores failures from Docker bind-mount conflicts
- Prunes `.git` directories from the walk

### Stack scripts

Shipped at `/etc/agent-sandbox/stacks/` in the base image. Each accepts an optional version argument and handles multi-arch (amd64/arm64). PATH additions use `/etc/zsh/zshenv.d/` drop-in files (zsh) and `/etc/profile.d/` (other shells).

## Tasks

### m6.1 - System-level shell-init sourcing

Move `source shell-init.sh` from `~/.zshrc` to `/etc/zsh/zshrc`.

- Create `images/base/system-zshrc`
- Modify `images/base/zshrc` (remove shell-init sourcing)
- Modify `images/base/shell-init.sh` (update comment)
- Modify `images/base/Dockerfile` (COPY system-zshrc)

### m6.2 - First-class dotfiles support

Recursive auto-symlink from `~/.dotfiles` at container startup.

- Create `images/base/link-dotfiles.sh`
- Modify `images/base/entrypoint.sh` (call link-dotfiles.sh)
- Modify `images/base/Dockerfile` (COPY link-dotfiles.sh)
- Update all 6 compose files (present dotfiles and individual file mounts as two options)

### m6.3 - Language stack scripts

Ship installer scripts in base image.

- Create `images/base/stacks/python.sh`
- Create `images/base/stacks/node.sh`
- Create `images/base/stacks/go.sh`
- Create `images/base/stacks/rust.sh`
- Modify `images/base/Dockerfile` (COPY stacks/, create zshenv.d/)

### m6.4 - STACKS build arg

Convenience wrapper in build.sh and base Dockerfile.

- Modify `images/build.sh` (STACKS and TAG env vars, pass STACKS to base build)
- Modify `images/base/Dockerfile` (STACKS ARG + RUN after zshenv.d setup)

### m6.5 - Documentation

- Update `templates/claude/README.md`
- Update `templates/copilot/README.md`
- Update `.claude/CLAUDE.md`
- Update `docs/plan/project.md`

## Definition of Done

- [ ] Custom .zshrc mount does not break shell.d scripts
- [ ] Dotfiles with nested .config files are properly linked
- [ ] Protected paths (.config/agent-sandbox) are not modified by dotfiles
- [ ] Each stack script installs correctly on arm64
- [ ] STACKS="python,go" build works end-to-end
- [ ] Template READMEs document all three features
- [ ] Published images (no stacks) still work unchanged
