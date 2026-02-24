# OpenAI Codex CLI agent image
# Extends base with Codex CLI binary from GitHub releases

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

# Create codex config directory, bake default config, ensure ~/.local/bin exists
RUN mkdir -p /home/dev/.codex /home/dev/.local/bin \
    && chown -R dev:dev /home/dev/.codex /home/dev/.local/bin
COPY config.toml /home/dev/.codex/config.toml
RUN chown dev:dev /home/dev/.codex/config.toml

USER dev

# Add ~/.local/bin to PATH (where the Codex binary will live)
ENV PATH="/home/dev/.local/bin:$PATH"

# Install Codex CLI binary from GitHub releases
# CODEX_VERSION: "latest" or a specific version like "0.104.0"
ARG CODEX_VERSION=latest
ARG TARGETARCH
RUN set -e && \
    case "$TARGETARCH" in \
      amd64) TRIPLE="x86_64-unknown-linux-musl" ;; \
      arm64) TRIPLE="aarch64-unknown-linux-musl" ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    ASSET="codex-${TRIPLE}.tar.gz" && \
    if [ "$CODEX_VERSION" = "latest" ]; then \
      URL="https://github.com/openai/codex/releases/latest/download/${ASSET}"; \
    else \
      URL="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${ASSET}"; \
    fi && \
    echo "Downloading Codex from ${URL}..." && \
    curl -fsSL "$URL" -o /tmp/codex.tar.gz && \
    tar -xzf /tmp/codex.tar.gz -C /tmp && \
    mv "/tmp/codex-${TRIPLE}" /home/dev/.local/bin/codex && \
    chmod +x /home/dev/.local/bin/codex && \
    rm /tmp/codex.tar.gz && \
    codex --version

LABEL org.opencontainers.image.description="Agent Sandbox with OpenAI Codex CLI"
LABEL com.mattolson.agentsandbox.codex-version="${CODEX_VERSION}"
