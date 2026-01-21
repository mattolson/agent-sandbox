# Devcontainer for agent-sandbox development
# Requires: run `./images/build.sh` first to build local images

ARG BASE_IMAGE=agent-sandbox-claude:local
FROM ${BASE_IMAGE}

# Override policy with VS Code + Claude Code endpoints
USER root
COPY policy.json /etc/agent-sandbox/policy.json
RUN chmod 644 /etc/agent-sandbox/policy.json
USER dev
