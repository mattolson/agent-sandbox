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
- Baking default policies into images is safe (agent can't modify the image) and provides good UX (works out of the box)
- Policy layering via Dockerfile COPY overwrites parent layer's policy cleanly
- Sudoers with specific script paths (not commands) restricts what users can escalate to; agent can sudo init-firewall.sh but not iptables directly
- Debian's default sudoers includes `env_reset`, which clears user environment variables; POLICY_FILE set by user won't pass through sudo
- HTTP_PROXY/HTTPS_PROXY env vars are opt-in; applications can ignore them and connect directly
- mitmproxy can read SNI (Server Name Indication) from TLS ClientHello without MITM decryption, enabling hostname logging for HTTPS
- Transparent proxy (iptables REDIRECT) works for same-container proxy but is complex for cross-container (requires TPROXY or custom routing)
- SSH allows tunneling (-D, -L, -R) which can bypass other network restrictions; blocking SSH entirely is simpler than trying to restrict it

## Architecture

- Devcontainer value diminishes when not using VS Code integrated terminal; compose-first may be cleaner for the core runtime
- "Baked default + optional override" pattern works well for security-sensitive config: ship sensible defaults in the image, allow power users to mount custom config from host (read-only, outside workspace)
- For sandboxing, separate enforcement from the sandboxed process: sidecar containers can't be killed/modified by the agent
- iptables as gatekeeper + proxy as enforcer is more robust than either alone: iptables ensures traffic goes through proxy, proxy does domain-level filtering
- Defense in depth works when layers serve different purposes; redundant enforcement at the same layer adds complexity without security benefit
- Devcontainers can use Docker Compose backend via `dockerComposeFile` in devcontainer.json, enabling sidecar patterns
- Relative paths in docker-compose files are resolved from the compose file's directory, not the project root; `.devcontainer/docker-compose.yml` needs `../` to reach repo root, not `../../`

## Security

- Threat model matters: sandboxing AI agents is about preventing unexpected network calls, not defending against actively malicious code trying to evade detection
- Privilege separation: run setup scripts as root, then drop to non-root user; non-root user can't modify iptables even if they can run specific sudo scripts
- Co-locating monitoring with the monitored process is weaker than external monitoring; process can kill/modify local monitors
- Environment variable-based proxy configuration is advisory, not enforced; must combine with network-level enforcement
- Allowing SSH to arbitrary hosts is equivalent to allowing arbitrary network access (tunneling)
- The Docker host network (172.x.0.0/24) being open to the agent is acceptable when other containers on that network are explicitly configured sidecars

## Process

- VS Code integrated terminal adds trailing whitespace on copy, making copied commands unusable; iTerm + docker exec is the workaround
- Documentation artifacts (schema docs, examples) belong in `docs/`, not in task execution directories
