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
RUN mise use -g claude-code@$CLAUDE_CODE_VERSION

ARG PYTHON_VERSION
RUN mise use -g python@$PYTHON_VERSION

ARG UV_VERSION
RUN mise use -g uv@$UV_VERSION

# Add Claude to PATH and set up aliases
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && \
  echo "alias claude='mise exec -- claude'" >> ~/.zshrc && \
  echo "alias yolo-claude='cd /workspace && claude --dangerously-skip-permissions'" >> ~/.zshrc && \
  echo "alias yc='yolo-claude'" >> ~/.zshrc

RUN mise exec -- \
    claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context claude-code --project "$(pwd)"

EXPOSE 24282