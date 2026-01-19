# Learnings

Lessons learned during project execution. Review at the start of each planning session.

## Technical

- iptables rules must preserve Docker's internal DNS resolution (127.0.0.11 NAT rules) or container DNS breaks
- `aggregate` tool is useful for collapsing GitHub's many IP ranges into fewer CIDR blocks
- VS Code devcontainers need `--cap-add=NET_ADMIN` and `--cap-add=NET_RAW` for iptables to work
- Policy schema should nest by concern (`egress:`, future `ingress:`, `mounts:`) for extensibility
- `yq` will be needed to parse YAML in the firewall script
- VS Code devcontainers bypass Docker ENTRYPOINT; use `postStartCommand` for runtime initialization that must run every container start
- Entrypoint scripts should be idempotent (check for existing state before acting) to support both devcontainer and compose workflows
- devcontainer.json and docker-compose.yml need separate volume/mount configs; they serve different workflows and VS Code reads devcontainer.json directly
- yq syntax `.foo // [] | .[]` safely iterates arrays that may be missing or null
- Policy files that control security must live outside the workspace and be mounted read-only; otherwise the agent can modify them and re-run initialization to bypass restrictions

## Architecture

- Devcontainer value diminishes when not using VS Code integrated terminal; compose-first may be cleaner for the core runtime
- "Baked default + optional override" pattern works well for security-sensitive config: ship sensible defaults in the image, allow power users to mount custom config from host (read-only, outside workspace)

## Process

- VS Code integrated terminal adds trailing whitespace on copy, making copied commands unusable; iTerm + docker exec is the workaround
- Documentation artifacts (schema docs, examples) belong in `docs/`, not in task execution directories
