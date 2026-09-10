# OpenAI Codex CLI agent image
# Extends base with Codex CLI binary from GitHub releases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Install bubblewrap so Codex's startup probe finds /usr/bin/bwrap.
# Optional extra packages can be layered on top via EXTRA_PACKAGES.
ARG EXTRA_PACKAGES=""
USER root
RUN set -e && \
    PACKAGES="bubblewrap" && \
    if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      PACKAGES="$PACKAGES $EXTRA_PACKAGES"; \
    fi && \
    apt-get update && apt-get install -y --no-install-recommends $PACKAGES \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Bake in the system codex config (can be overridden at user or project level)
RUN mkdir -p /etc/codex
COPY config.toml /etc/codex/config.toml

# Create codex config directory and ensure ~/.local/bin exists (default destination for codex binary)
RUN mkdir -p /home/dev/.codex /home/dev/.local/bin \
    && chown -R dev:dev /home/dev/.codex /home/dev/.local

USER dev

# Add ~/.local/bin to PATH (where the Codex binary will live)
ENV PATH="/home/dev/.local/bin:$PATH"

# Tell Codex where its config/state lives
ENV CODEX_HOME="/home/dev/.codex"

# Install Codex CLI binaries from GitHub releases
# CODEX_VERSION: "latest" or a specific version like "0.104.0"
#
# Codex ships as separate per-binary archives. The main `codex` binary is
# required. `codex-code-mode-host` is the Code Mode helper that Codex looks for
# next to its own executable; without it every session warns that Code Mode is
# unavailable. Releases before it existed simply do not publish the asset, so a
# 404 for the host is tolerated with a warning while any other failure aborts.
ARG CODEX_VERSION=latest
ARG TARGETARCH
RUN set -e && \
    case "$TARGETARCH" in \
      amd64) TRIPLE="x86_64-unknown-linux-musl" ;; \
      arm64) TRIPLE="aarch64-unknown-linux-musl" ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    if [ "$CODEX_VERSION" = "latest" ]; then \
      BASE_URL="https://github.com/openai/codex/releases/latest/download"; \
    else \
      BASE_URL="https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}"; \
    fi && \
    for BIN in codex codex-code-mode-host; do \
      ASSET="${BIN}-${TRIPLE}.tar.gz" && \
      URL="${BASE_URL}/${ASSET}" && \
      echo "Downloading ${BIN} from ${URL}..." && \
      STATUS=$(curl -sSL -w '%{http_code}' -o "/tmp/${ASSET}" "$URL") && \
      if [ "$STATUS" != "200" ]; then \
        rm -f "/tmp/${ASSET}"; \
        if [ "$BIN" != "codex" ] && [ "$STATUS" = "404" ]; then \
          echo "WARNING: ${ASSET} not published for this release (HTTP 404); skipping ${BIN}" >&2; \
          continue; \
        fi; \
        echo "ERROR: failed to download ${URL} (HTTP ${STATUS})" >&2; \
        exit 1; \
      fi && \
      tar -xzf "/tmp/${ASSET}" -C /tmp && \
      mv "/tmp/${BIN}-${TRIPLE}" "/home/dev/.local/bin/${BIN}" && \
      chmod +x "/home/dev/.local/bin/${BIN}" && \
      rm "/tmp/${ASSET}"; \
    done && \
    codex --version

LABEL org.opencontainers.image.description="Agent Sandbox with OpenAI Codex CLI"
LABEL com.mattolson.agentsandbox.codex-version="${CODEX_VERSION}"
