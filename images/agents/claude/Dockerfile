# Claude Code agent image
# Extends base with Claude Code CLI

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Optional extra packages
ARG EXTRA_PACKAGES=""
USER root
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      apt-get update && apt-get install -y --no-install-recommends $EXTRA_PACKAGES \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

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
