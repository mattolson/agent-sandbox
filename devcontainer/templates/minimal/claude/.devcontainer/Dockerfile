# Claude Code Sandbox
#
# Requires: Build images first from the agent-sandbox repo:
#   git clone https://github.com/mattolson/agent-sandbox.git
#   cd agent-sandbox && ./images/build.sh
#
# Once images are published to GHCR (m2), this will use:
#   ARG BASE_IMAGE=ghcr.io/mattolson/agent-sandbox-claude@sha256:...

ARG BASE_IMAGE=agent-sandbox-claude:local
FROM ${BASE_IMAGE}

# Copy project policy (customize policy.yaml to add domains)
USER root
COPY policy.yaml /etc/agent-sandbox/policy.yaml
RUN chmod 644 /etc/agent-sandbox/policy.yaml
USER dev
