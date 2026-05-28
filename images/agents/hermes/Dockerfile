# Nous Research Hermes agent image
# Extends base with hermes-agent installed from PyPI into a dedicated venv.

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Optional extra packages
ARG EXTRA_PACKAGES=""
USER root
RUN set -e && \
    PACKAGES="python3 python3-venv" && \
    if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      PACKAGES="$PACKAGES $EXTRA_PACKAGES"; \
    fi && \
    apt-get update && apt-get install -y --no-install-recommends $PACKAGES \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install hermes-agent from PyPI into a dedicated venv at /opt/hermes/.venv.
# Upstream maintains two version tracks: PyPI uses semver (e.g. 0.14.0) while
# git tags use calver (e.g. v2026.5.16); they refer to the same release.
# HERMES_VERSION uses the PyPI form. "latest" is treated as a sentinel and
# resolves to whatever PyPI is currently shipping at build time (CI overrides
# this with the explicit version from the PyPI query step).
ARG HERMES_VERSION=latest
RUN python3 -m venv /opt/hermes/.venv && \
    if [ "$HERMES_VERSION" = "latest" ]; then \
      /opt/hermes/.venv/bin/pip install --no-cache-dir "hermes-agent"; \
    else \
      /opt/hermes/.venv/bin/pip install --no-cache-dir "hermes-agent==${HERMES_VERSION}"; \
    fi && \
    ln -s /opt/hermes/.venv/bin/hermes /usr/local/bin/hermes && \
    chmod -R a+rX /opt/hermes && \
    hermes --version

# Create hermes state directory (HERMES_HOME default is ~/.hermes)
RUN mkdir -p /home/dev/.hermes && chown -R dev:dev /home/dev/.hermes

USER dev

ENV HERMES_HOME="/home/dev/.hermes" \
    HERMES_YOLO_MODE=1 \
    HERMES_DISABLE_LAZY_INSTALLS=1 \
    HERMES_MANAGED=AgentSandbox

LABEL org.opencontainers.image.description="Agent Sandbox with Nous Research Hermes agent"
LABEL com.mattolson.agentsandbox.hermes-version="${HERMES_VERSION}"
