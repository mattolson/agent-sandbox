# Claude Code Sandbox
#
# Uses published image from GitHub Container Registry.
# For reproducibility, pin to a specific digest:
#   ARG BASE_IMAGE=ghcr.io/mattolson/agent-sandbox-claude@sha256:<digest>
#
# For local development, override with:
#   docker build --build-arg BASE_IMAGE=agent-sandbox-claude:local .

ARG BASE_IMAGE=ghcr.io/mattolson/agent-sandbox-claude:latest
FROM ${BASE_IMAGE}

# Copy project policy (customize policy.json to add domains)
USER root
COPY policy.json /etc/agent-sandbox/policy.json
RUN chmod 644 /etc/agent-sandbox/policy.json
USER dev
