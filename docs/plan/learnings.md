# Learnings

Lessons learned during project execution. Review at the start of each planning session.

## Technical

- iptables rules must preserve Docker's internal DNS resolution (127.0.0.11 NAT rules) or container DNS breaks
- `aggregate` tool is useful for collapsing GitHub's many IP ranges into fewer CIDR blocks
- VS Code devcontainers need `--cap-add=NET_ADMIN` and `--cap-add=NET_RAW` for iptables to work
- Policy schema should nest by concern (`egress:`, future `ingress:`, `mounts:`) for extensibility
- `yq` will be needed to parse YAML in the firewall script

## Architecture

- Devcontainer value diminishes when not using VS Code integrated terminal; compose-first may be cleaner for the core runtime

## Process

- VS Code integrated terminal adds trailing whitespace on copy, making copied commands unusable; iTerm + docker exec is the workaround
- Documentation artifacts (schema docs, examples) belong in `docs/`, not in task execution directories
