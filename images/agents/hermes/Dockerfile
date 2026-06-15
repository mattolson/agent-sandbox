# Nous Research Hermes agent image
# Extends base with hermes-agent installed from a pinned git checkout as an
# editable install into a sibling venv. The git layout (a real .git directory
# in the source tree) makes upstream's detect_install_method() resolve to
# "git", which suppresses the "pip install not officially supported" launch
# banner and lets us bake a curated extras set instead of the wheel's empty
# one. See docs/agents/hermes.md and
# docs/plan/milestones/m16-hermes/tasks/m16.8-git-install/task.md.

ARG BASE_IMAGE=agent-sandbox-base:local
FROM ${BASE_IMAGE}

# Optional extra apt packages (validated below). base already provides git,
# build-essential, curl, ripgrep, and ca-certificates; only Python is missing.
ARG EXTRA_PACKAGES=""
USER root
RUN set -e && \
    PACKAGES="python3" && \
    if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      PACKAGES="$PACKAGES $EXTRA_PACKAGES"; \
    fi && \
    apt-get update && apt-get install -y --no-install-recommends $PACKAGES \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# python3-dev is deliberately omitted: the chosen extras (cli/mcp/acp) plus core
# resolve as prebuilt wheels. If a future dep needs to compile from source, add
# python3-dev here (build-essential is already in the base image).

# Install uv (build-time only) for the locked, editable install below.
ARG UV_VERSION=latest
RUN set -e && \
    if [ "$UV_VERSION" = "latest" ]; then \
      curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh; \
    else \
      curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh; \
    fi && \
    uv --version

# Pin the upstream release. HERMES_REF is the calver git tag (e.g. v2026.6.5);
# HERMES_SEMVER is the human-facing semver (e.g. 0.16.0) carried in a label
# only. Upstream maintains both schemes for the same release with no link from
# PyPI to the tag, so the build clones the tag and CI resolves both from the
# GitHub release. The default here is a concrete tag for bare `docker build`;
# build.sh and CI override it. Bump via the version-check workflow.
ARG HERMES_REF=v2026.6.5
ARG HERMES_SEMVER=${HERMES_REF}

# Curated extras (comma-separated). cli = interactive menus, mcp = Model Context
# Protocol client, acp = Agent Client Protocol. Deliberately excludes web
# (dashboard) and all lazy-only backends. cron/pty are empty upstream no-ops.
ARG HERMES_EXTRAS="cli,mcp,acp"

# Shallow-clone the pinned tag (keep .git — detect_install_method() keys on it),
# then editable-install core + the curated extras from the locked uv.lock into a
# sibling .venv. The .venv beside the source is exactly the layout `hermes
# doctor` probes for, so its "Reinstall entry point" check passes natively (no
# site-packages symlink hack). The source lives at /opt/hermes/hermes-agent,
# outside the HERMES_HOME state volume, so the runtime mount never shadows it.
ENV UV_NO_CACHE=1 UV_LINK_MODE=copy
RUN set -e && \
    git clone --depth 1 --branch "$HERMES_REF" \
      https://github.com/NousResearch/hermes-agent.git /opt/hermes/hermes-agent && \
    cd /opt/hermes/hermes-agent && \
    EXTRA_FLAGS="" && \
    for e in $(printf '%s' "$HERMES_EXTRAS" | tr ',' ' '); do EXTRA_FLAGS="$EXTRA_FLAGS --extra $e"; done && \
    uv sync --locked --python python3 $EXTRA_FLAGS && \
    /opt/hermes/hermes-agent/.venv/bin/hermes --version

# Work around upstream hermes-agent#15768: setup's free-text prompts call bare
# input() without importing readline, so arrow keys leak escape sequences.
# site.py auto-imports any sitecustomize module at interpreter startup, so this
# enables readline for every Python invocation under this venv — and nowhere
# else. Curses menus are unaffected. See docs/agents/hermes.md.
RUN SITE_PACKAGES="$(/opt/hermes/hermes-agent/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    printf 'try:\n    import readline  # noqa: F401\nexcept ImportError:\n    pass\n' > "$SITE_PACKAGES/sitecustomize.py"

# Lock the install down: root-owned and not writable by dev. This — not the
# wrapper — is what blocks self-upgrade (no editable-source edits, no `git
# pull`). See the security note in docs/agents/hermes.md.
RUN chown -R root:root /opt/hermes && chmod -R a+rX /opt/hermes

# Install the update/uninstall-intercepting wrapper on PATH. It execs the real
# venv entry point, which is left untouched: renaming it would break `hermes
# gateway` status detection (which scans process cmdlines for ".../hermes
# gateway") and change the CLI's program name. We deliberately do NOT plant
# ~/.local/bin/hermes — doctor's "Command Installation" check expects it, but
# pointing it at the real binary would shadow this wrapper on PATH (update
# bypass) and pointing it at the wrapper fails doctor's strict equality check.
# We accept the one cosmetic doctor note. See hermes-wrapper.sh and
# docs/agents/hermes.md.
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
LABEL com.mattolson.agentsandbox.hermes-version="${HERMES_SEMVER}"
LABEL com.mattolson.agentsandbox.hermes-ref="${HERMES_REF}"
