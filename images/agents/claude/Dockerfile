# Claude Code agent image
# Extends base with Claude Code CLI and convenience aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Copy aliases file (sourced by shell-init.sh)
USER root
COPY aliases.sh /etc/agent-sandbox/aliases.sh
RUN chmod 644 /etc/agent-sandbox/aliases.sh

# Create claude config directory
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code via official install script
# CLAUDE_CODE_VERSION is determined by the build workflow and used for image tagging
ARG CLAUDE_CODE_VERSION=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s $CLAUDE_CODE_VERSION

# Add Claude to PATH (install script puts it in ~/.local/bin)
ENV PATH="/home/dev/.local/bin:$PATH"

LABEL org.opencontainers.image.description="Agent Sandbox with Claude Code"
LABEL com.mattolson.agentsandbox.claude-code-version="${CLAUDE_CODE_VERSION}"
