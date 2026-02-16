# Pi Coding Agent image
# Extends base with Pi CLI installed via npm

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Optional extra packages
ARG PI_EXTRA_PACKAGES=""
USER root
RUN if [ -n "$PI_EXTRA_PACKAGES" ]; then \
      printf '%s' "$PI_EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: PI_EXTRA_PACKAGES contains invalid characters: $PI_EXTRA_PACKAGES" >&2; exit 1; }; \
      apt-get update && apt-get install -y --no-install-recommends $PI_EXTRA_PACKAGES \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Install Node.js (required for npm) via NodeSource apt repo with GPG verification
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.key && \
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.key && \
    rm /tmp/nodesource.key && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y nodejs ripgrep fd-find && \
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create pi config directory
RUN mkdir -p /home/dev/.pi && chown -R dev:dev /home/dev/.pi

# Install Pi CLI via npm - must be root for global install
ARG PI_VERSION=latest
RUN npm install -g @mariozechner/pi-coding-agent@${PI_VERSION}

USER dev

LABEL org.opencontainers.image.description="Agent Sandbox with Pi Coding Agent"
LABEL com.mattolson.agentsandbox.pi-version="${PI_VERSION}"
