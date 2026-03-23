# Factory CLI agent image
# Extends base with Factory CLI installed via npm

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

# Install Node.js (required for npm) via NodeSource apt repo with GPG verification, and xdg-utils
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.key && \
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.key && \
    rm /tmp/nodesource.key && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y nodejs xdg-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create factory config directory
RUN mkdir -p /home/dev/.factory && chown -R dev:dev /home/dev/.factory

# Install Factory CLI via npm - must be root for global install
ARG FACTORY_VERSION=latest
RUN npm install -g droid@${FACTORY_VERSION}

USER dev

LABEL org.opencontainers.image.description="Agent Sandbox with Factory CLI"
LABEL com.mattolson.agentsandbox.factory-version="${FACTORY_VERSION}"
