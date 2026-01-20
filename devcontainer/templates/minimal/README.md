# Minimal Template

Network-locked sandbox using iptables-based egress control.

## How it works

1. Container starts with `NET_ADMIN` and `NET_RAW` capabilities
2. `init-firewall.sh` runs at startup via entrypoint (compose) or postStartCommand (devcontainer)
3. Script reads policy.yaml and creates iptables rules that DROP all outbound traffic except to allowed destinations
4. Allowed IPs are stored in an ipset for efficient matching

## Characteristics

- Simple: just iptables rules, no proxy
- DNS resolution happens at container start (IPs are cached)
- Works offline after initial setup
- No request-level logging (use proxy-locked template for that)

## Available agents

- [claude/](./claude/) - Claude Code sandbox

## Adding new agents

Create a new directory with:
- `.devcontainer/devcontainer.json` - VS Code config
- `.devcontainer/Dockerfile` - extends the agent's base image
- `.devcontainer/policy.yaml` - network allowlist
- `docker-compose.yml` - standalone mode config

See [claude/](./claude/) for reference.
