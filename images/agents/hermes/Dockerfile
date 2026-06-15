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

# Install a pinned, checksum-verified uv (build-time only) for the locked,
# editable install below. Download the binary straight from the GitHub release
# instead of piping the installer to sh, so a compromised CDN/DNS can't
# substitute a malicious binary. Bump UV_VERSION and both SHA-256s together from
# the release's <asset>.sha256 files.
ARG UV_VERSION=0.11.21
ARG UV_SHA256_AMD64=8c88519b0ef0af9801fcdee419bbb12116bd9e6b18e162ae093c932d8b264050
ARG UV_SHA256_ARM64=88e800834007cc5efd4675f166eb2a51e7e3ad19876d85fa8805a6fb5c922397
ARG TARGETARCH
RUN set -e && \
    case "$TARGETARCH" in \
      amd64) UV_TRIPLE=x86_64-unknown-linux-gnu; UV_SHA="$UV_SHA256_AMD64" ;; \
      arm64) UV_TRIPLE=aarch64-unknown-linux-gnu; UV_SHA="$UV_SHA256_ARM64" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/uv.tar.gz \
      "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TRIPLE}.tar.gz" && \
    echo "${UV_SHA}  /tmp/uv.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/uv.tar.gz -C /tmp && \
    install -m 0755 "/tmp/uv-${UV_TRIPLE}/uv" /usr/local/bin/uv && \
    rm -rf /tmp/uv.tar.gz "/tmp/uv-${UV_TRIPLE}" && \
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
    if [ -n "$HERMES_EXTRAS" ]; then \
      printf '%s' "$HERMES_EXTRAS" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9._,-]*$' \
        || { echo "ERROR: HERMES_EXTRAS contains invalid characters: $HERMES_EXTRAS" >&2; exit 1; }; \
    fi && \
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

# Lock the install down: root-owned and read-only for dev. This is what makes
# self-upgrade impossible — `hermes update` (or a direct `git pull`) fails on the
# read-only, root-owned checkout. There is no in-sandbox upgrade path; rebuild
# the image instead (see docs/agents/hermes.md). We deliberately do NOT wrap or
# intercept `hermes update`: a wrapper added more failure modes (gateway status
# detection, doctor symlink equality) than the error message it dressed up.
RUN chown -R root:root /opt/hermes && chmod -R a+rX /opt/hermes

# Put the real, unmodified hermes on PATH. /usr/local/bin is always on PATH;
# ~/.local/bin is where `hermes doctor`'s "Command Installation" check looks (the
# upstream installer drops it there). Both symlink straight to the venv entry
# point, so gateway status detection and the CLI program name are unaffected.
RUN ln -s /opt/hermes/hermes-agent/.venv/bin/hermes /usr/local/bin/hermes && \
    mkdir -p /home/dev/.local/bin && \
    ln -s /opt/hermes/hermes-agent/.venv/bin/hermes /home/dev/.local/bin/hermes && \
    chown -R dev:dev /home/dev/.local

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
