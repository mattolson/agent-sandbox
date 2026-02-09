# GitHub Copilot CLI agent image
# Extends base with Copilot CLI installed via npm

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
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create copilot config directory
RUN mkdir -p /home/dev/.copilot && chown -R dev:dev /home/dev/.copilot

# Install Copilot CLI via npm - must be root for global install
ARG COPILOT_VERSION=latest
RUN npm install -g @github/copilot@${COPILOT_VERSION}

USER dev

LABEL org.opencontainers.image.description="Agent Sandbox with GitHub Copilot CLI"
LABEL com.mattolson.agentsandbox.copilot-version="${COPILOT_VERSION}"
