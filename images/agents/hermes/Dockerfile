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
    chmod -R a+rX /opt/hermes && \
    /opt/hermes/.venv/bin/hermes --version

# Silence `hermes doctor`'s "Reinstall entry point" false positive. Doctor
# resolves PROJECT_ROOT from hermes_cli/config.py via Path(__file__).parent.parent,
# which on a PyPI/venv install lands at site-packages and then probes for a
# sibling venv at PROJECT_ROOT/{venv,.venv}/bin/hermes — a layout that only
# exists for `pip install -e .` development checkouts. Plant the symlink doctor
# expects so the check passes. See docs/agents/hermes.md.
RUN SITE_PACKAGES="$(/opt/hermes/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    mkdir -p "$SITE_PACKAGES/.venv/bin" && \
    ln -s /opt/hermes/.venv/bin/hermes "$SITE_PACKAGES/.venv/bin/hermes"

# Plant the ~/.local/bin/hermes symlink doctor's "Command Installation" check
# expects. Doctor compares the resolved target against the venv entry point,
# so we point at /opt/hermes/.venv/bin/hermes (not /usr/local/bin/hermes).
# Our wrapper still wins for `hermes <subcmd>` because ~/.local/bin is not on
# PATH in the base image, so update/uninstall interception stays intact. When
# the symlink is already correct, doctor also skips its "directory on PATH?"
# follow-up check. See docs/agents/hermes.md.
RUN mkdir -p /home/dev/.local/bin && \
    ln -s /opt/hermes/.venv/bin/hermes /home/dev/.local/bin/hermes && \
    chown -R dev:dev /home/dev/.local

# Work around upstream hermes-agent#15768: setup's free-text prompts (API
# keys, file paths, y/n confirmations) call bare input() without ever
# importing readline, so arrow keys leak escape sequences as literal text
# instead of doing line editing. Python's site.py auto-imports any module
# named sitecustomize at interpreter startup, so dropping one into the venv
# site-packages enables readline for every Python invocation under this
# venv — and nowhere else. Curses menus are unaffected; this only restores
# behavior at input() prompts. See docs/agents/hermes.md.
RUN SITE_PACKAGES="$(/opt/hermes/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    printf 'try:\n    import readline  # noqa: F401\nexcept ImportError:\n    pass\n' > "$SITE_PACKAGES/sitecustomize.py"

# Install the wrapper that intercepts `hermes update` / `hermes uninstall`
# with a clean message. See hermes-wrapper.sh for the rationale.
COPY hermes-wrapper.sh /usr/local/bin/hermes
RUN chmod 0755 /usr/local/bin/hermes

# Launch script for the image's default command. Starts the gateway in the
# background and keeps the container alive independently. See the script.
COPY hermes-gateway-launch.sh /usr/local/bin/hermes-gateway-launch
RUN chmod 0755 /usr/local/bin/hermes-gateway-launch

# Create hermes state directory (HERMES_HOME default is ~/.hermes)
RUN mkdir -p /home/dev/.hermes && chown -R dev:dev /home/dev/.hermes

USER dev

ENV HERMES_HOME="/home/dev/.hermes" \
    HERMES_YOLO_MODE=1 \
    HERMES_DISABLE_LAZY_INSTALLS=1

# Default the image to launching the gateway in the background while keeping
# the container alive (see hermes-gateway-launch). Overrides the base image's
# `sleep infinity`. Override via the compose `command:` in a user override
# file for a different default process.
CMD ["hermes-gateway-launch"]

LABEL org.opencontainers.image.description="Agent Sandbox with Nous Research Hermes agent"
LABEL com.mattolson.agentsandbox.hermes-version="${HERMES_VERSION}"
