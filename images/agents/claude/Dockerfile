# Claude Code agent image
# Extends base with Claude Code CLI and aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Override base policy with Claude Code endpoints
USER root
COPY policy.yaml /etc/agent-sandbox/policy.yaml
RUN chmod 644 /etc/agent-sandbox/policy.yaml

# Create claude config directory
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code
ARG CLAUDE_CODE_VERSION=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s $CLAUDE_CODE_VERSION

# Add Claude to PATH and set up aliases
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && \
  echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> ~/.zshrc && \
  echo "alias yc='yolo-claude'" >> ~/.zshrc
