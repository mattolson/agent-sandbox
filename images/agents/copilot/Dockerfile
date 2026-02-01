# GitHub Copilot CLI agent image
# Extends base with Copilot CLI installed via npm

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Install Node.js (required for npm)
USER root
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create copilot config directory
RUN mkdir -p /home/dev/.copilot && chown -R dev:dev /home/dev/.copilot

# Install Copilot CLI via npm - must be root for global install
ARG COPILOT_VERSION=latest
RUN npm install -g @github/copilot@${COPILOT_VERSION}

USER dev

LABEL org.opencontainers.image.description="Agent Sandbox with GitHub Copilot CLI"
LABEL com.mattolson.agentsandbox.copilot-version="${COPILOT_VERSION}"
