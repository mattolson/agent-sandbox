# OpenCode agent image
# Extends base with OpenCode CLI installed via npm

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

# Install Node.js (required for npm) via NodeSource apt repo with GPG verification
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.key && \
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.key && \
    rm /tmp/nodesource.key && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create XDG directories for OpenCode
RUN mkdir -p /home/dev/.config/opencode /home/dev/.local/share/opencode /home/dev/.local/state/opencode /home/dev/.cache/opencode \
    && chown -R dev:dev /home/dev/.config /home/dev/.local /home/dev/.cache

# Install OpenCode via npm - must be root for global install
ARG OPENCODE_VERSION=latest
RUN npm install -g opencode-ai@${OPENCODE_VERSION}

# Bake default config for yolo mode (all permissions allowed)
COPY opencode.json /home/dev/.config/opencode/opencode.json
RUN chown dev:dev /home/dev/.config/opencode/opencode.json

USER dev

# Disable auto-update and LSP download inside the sandbox
ENV OPENCODE_DISABLE_AUTOUPDATE=true
ENV OPENCODE_DISABLE_LSP_DOWNLOAD=true

LABEL org.opencontainers.image.description="Agent Sandbox with OpenCode agent"
LABEL ai.opencode.version="${OPENCODE_VERSION}"
