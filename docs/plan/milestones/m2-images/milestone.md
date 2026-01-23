# m2-images

Build and publish images to GitHub Container Registry so users don't need to build locally.

## Goals

- Set up GitHub Actions to build and publish images
- Update template to use published images with digest pinning
- Document image update process

## Current State

From M1:
- `images/base/Dockerfile` - base image with tools, firewall, zsh
- `images/agents/claude/Dockerfile` - extends base with Claude Code
- `images/build.sh` - local build script

Users currently must clone the repo and run `./images/build.sh` before using templates.

## Design Decisions

### Registry

**Decision**: GitHub Container Registry (ghcr.io)

- Free for public repos
- Native GitHub Actions integration
- No separate account needed

Image names:
- `ghcr.io/mattolson/agent-sandbox-base`
- `ghcr.io/mattolson/agent-sandbox-claude`

### Build Triggers

**Decision**: Build on push to main (with path filter) AND on release tags

- Push to main: builds with `latest` tag and `sha-<commit>` tag
  - Only when `images/**` or workflow file changes
  - Docs-only changes don't trigger builds
- Release tag (v*): builds with version tag (e.g., `v1.0.0`)
  - Always builds regardless of paths

This gives users a choice:
- `latest` for always-current (less stable)
- `v1.0.0` for pinned version (more stable)
- `@sha256:...` for exact reproducibility

Always build both images together when triggered (base + claude) to avoid missing cascading changes.

### Digest Pinning

**Decision**: Template uses digest pinning by default

```dockerfile
ARG BASE_IMAGE=ghcr.io/mattolson/agent-sandbox-claude@sha256:abc123...
FROM ${BASE_IMAGE}
```

Users can override with `--build-arg BASE_IMAGE=...` for local dev or different versions.

### Multi-arch Support

**Decision**: Build for both amd64 and arm64

- Use QEMU emulation in GitHub Actions for cross-platform builds
- Publish manifest list that includes both architectures
- Docker automatically pulls the correct architecture for the host
- Native arm64 for Apple Silicon (no Rosetta emulation needed)

## Tasks

### m2.1-github-actions

Set up GitHub Actions workflow for building images.

- Create `.github/workflows/build-images.yml`
- Build on push to main (latest + sha tag)
- Build on version tags (version tag)
- Push to ghcr.io
- Output image digests

### m2.2-update-template

Update template to use published images.

- Change Dockerfile FROM to use ghcr.io with digest
- Update README with digest update instructions
- Keep local build option via build-arg

### m2.3-docs

Document image versioning and updates.

- How to update to latest digest
- Version policy (when we bump major/minor/patch)
- How to use local builds for development

## Definition of Done

- [x] GitHub Actions builds and pushes images on merge to main
- [x] GitHub Actions builds and pushes images on version tags
- [x] Template references ghcr.io images with digest
- [x] Template README documents how to update digest
- [x] Images are publicly pullable without auth
- [x] Multi-arch support (amd64 + arm64)

## Open Questions

1. Should we automate digest updates (dependabot, renovate)? Defer to M3 CLI?
2. Do we need a separate workflow for PRs (build but don't push)?

## Notes

- GHCR auth uses `GITHUB_TOKEN` which is automatic in Actions
- Public packages are readable without auth after first push
- First push requires manual package visibility toggle to public
