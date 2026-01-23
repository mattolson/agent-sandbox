# Claude Code agent image
# Extends base with Claude Code CLI and convenience aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Override base policy with Claude Code endpoints
# Copy aliases file (sourced by base image's .zshrc)
USER root
COPY policy.yaml /etc/agent-sandbox/policy.yaml
COPY aliases.sh /etc/agent-sandbox/aliases.sh
RUN chmod 644 /etc/agent-sandbox/policy.yaml /etc/agent-sandbox/aliases.sh

# Create claude config directory
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code
ARG CLAUDE_CODE_VERSION=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s $CLAUDE_CODE_VERSION

# Add Claude to PATH
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
