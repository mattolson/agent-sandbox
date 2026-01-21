# Claude Code agent image
# Extends base with Claude Code CLI and aliases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Override base policy with Claude Code endpoints
USER root

# Install mise via official APT repo
RUN install -dm 755 /etc/apt/keyrings && \
  curl -fsSL https://mise.jdx.dev/gpg-key.pub \
    | tee /etc/apt/keyrings/mise-archive-keyring.asc > /dev/null && \
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" \
    > /etc/apt/sources.list.d/mise.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends mise && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

COPY policy.json /etc/agent-sandbox/policy.json
RUN chmod 644 /etc/agent-sandbox/policy.json

# Create claude config directory
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude
USER dev

# Install Claude Code
ARG CLAUDE_CODE_VERSION=latest
RUN mise use -g claude-code@$CLAUDE_CODE_VERSION

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
