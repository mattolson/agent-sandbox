# Factory CLI agent image
# Extends base with Factory CLI binary

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

# Create factory config directory and ensure ~/.local/bin exists
RUN mkdir -p /home/dev/.factory /home/dev/.local/bin \
    && chown -R dev:dev /home/dev/.factory /home/dev/.local

USER dev

# Add ~/.local/bin to PATH (in case the script installs there)
ENV PATH="/home/dev/.local/bin:$PATH"

# Install Factory CLI binary via the script
ARG FACTORY_VERSION=latest
RUN curl -fsSL https://app.factory.ai/cli | sh

LABEL org.opencontainers.image.description="Agent Sandbox with Factory CLI"
LABEL com.mattolson.agentsandbox.factory-version="${FACTORY_VERSION}"
