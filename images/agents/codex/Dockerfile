# OpenAI Codex CLI agent image
# Extends base with Codex CLI binary from GitHub releases

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Install system bubblewrap. Codex looks for bwrap on PATH at startup and warns
# when it is missing, even though the package bundles codex-resources/bwrap as
# a fallback.
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

# Install Codex CLI from GitHub releases
# CODEX_VERSION: "latest" or a specific version like "X.Y.Z"
#
# Releases ship a complete package archive (bin/codex,
# bin/codex-code-mode-host, codex-path/rg, codex-resources/bwrap, and
# codex-package.json). The codex binary refuses to start unless it runs from
# inside that layout, so the package is unpacked to /opt/codex and only the
# entrypoint is symlinked onto PATH. The archive is verified against the
# release's codex-package_SHA256SUMS. Releases that predate the package are
# not supported; any download failure aborts the build.
ARG CODEX_VERSION=latest
ARG TARGETARCH
USER root
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
    PACKAGE="codex-package-${TRIPLE}.tar.gz" && \
    for ASSET in "$PACKAGE" codex-package_SHA256SUMS; do \
      echo "Downloading ${BASE_URL}/${ASSET}..." && \
      STATUS=$(curl -sSL -w '%{http_code}' -o "/tmp/${ASSET}" "${BASE_URL}/${ASSET}") && \
      if [ "$STATUS" != "200" ]; then \
        echo "ERROR: failed to download ${BASE_URL}/${ASSET} (HTTP ${STATUS})" >&2; \
        exit 1; \
      fi; \
    done && \
    EXPECTED=$(awk -v a="$PACKAGE" '$2 == a { print tolower($1); exit }' /tmp/codex-package_SHA256SUMS) && \
    if [ -z "$EXPECTED" ]; then \
      echo "ERROR: no checksum for ${PACKAGE} in codex-package_SHA256SUMS" >&2; \
      exit 1; \
    fi && \
    echo "${EXPECTED}  /tmp/${PACKAGE}" | sha256sum -c - && \
    mkdir -p /opt/codex && \
    tar --no-same-owner -xzf "/tmp/${PACKAGE}" -C /opt/codex && \
    for f in codex-package.json bin/codex bin/codex-code-mode-host codex-path/rg codex-resources/bwrap; do \
      [ -e "/opt/codex/$f" ] || { echo "ERROR: package is missing $f" >&2; exit 1; }; \
    done && \
    chmod 0755 /opt/codex/bin/codex /opt/codex/bin/codex-code-mode-host \
      /opt/codex/codex-path/rg /opt/codex/codex-resources/bwrap && \
    ln -sf /opt/codex/bin/codex /home/dev/.local/bin/codex && \
    rm -f "/tmp/${PACKAGE}" /tmp/codex-package_SHA256SUMS
USER dev
RUN codex --version

LABEL org.opencontainers.image.description="Agent Sandbox with OpenAI Codex CLI"
LABEL com.mattolson.agentsandbox.codex-version="${CODEX_VERSION}"
