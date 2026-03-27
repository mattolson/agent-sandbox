ARG YQ_VERSION=4.52.4

FROM debian:bookworm-slim AS git-builder

ARG GIT_VERSION=2.50.1
ARG GIT_TARBALL_SHA256=4932f262b88b7f4f8402e331a7ee8d0a98ba350aa2269ce3a00eeda18cb4fe43

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  libcurl4-openssl-dev \
  libexpat1-dev \
  libpcre2-dev \
  libssl-dev \
  perl \
  zlib1g-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN curl -fsSL "https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz" -o git.tar.gz && \
  echo "${GIT_TARBALL_SHA256}  git.tar.gz" | sha256sum -c - && \
  tar -xzf git.tar.gz && \
  cd "git-${GIT_VERSION}" && \
  make prefix=/usr/local NO_GETTEXT=YesPlease NO_TCLTK=YesPlease -j"$(nproc)" all && \
  make prefix=/usr/local NO_GETTEXT=YesPlease NO_TCLTK=YesPlease install

FROM mikefarah/yq:${YQ_VERSION} AS yq-builder

FROM debian:bookworm-slim

ARG TZ
ARG YQ_VERSION
ENV TZ="$TZ"

# Install basic development tools and firewall dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  fzf \
  gnupg2 \
  iptables \
  ipset \
  iproute2 \
  jq \
  less \
  perl \
  procps \
  ripgrep \
  sudo \
  tmux \
  unzip \
  vim \
  zsh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Keep yq aligned with the CLI's mikefarah/yq-based behavior instead of
# Debian's unrelated yq package.
COPY --from=yq-builder /usr/bin/yq /usr/local/bin/yq
RUN yq --version | grep -F "v${YQ_VERSION}"

# Optional extra packages (separate layer for cacheability)
ARG EXTRA_PACKAGES=""
RUN if [ -n "$EXTRA_PACKAGES" ]; then \
      printf '%s' "$EXTRA_PACKAGES" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.+ :-]*$' \
        || { echo "ERROR: EXTRA_PACKAGES contains invalid characters: $EXTRA_PACKAGES" >&2; exit 1; }; \
      apt-get update && apt-get install -y --no-install-recommends $EXTRA_PACKAGES \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# Set up non-root user
ARG USERNAME=dev
RUN groupadd --system --gid 500 ${USERNAME} && useradd --system --create-home --uid 500 --gid 500 --shell /bin/bash ${USERNAME}

# Persist shell history (docker volume)
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history /commandhistory/.zsh_history \
  && chown -R ${USERNAME} /commandhistory

# Set environment variables
ENV DEVCONTAINER=true

# Create workspace and config directories
RUN mkdir -p /workspace && chown -R ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

# Debian bookworm ships Git 2.39.5, which cannot create relative worktree
# metadata even if worktree.useRelativePaths is configured.
COPY --from=git-builder /usr/local/ /usr/local/

USER ${USERNAME}

# Set default shell and editor
ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim
ENV COLORTERM=truecolor

# Set default lang to support unicode characters
ENV LANG=C.utf8

# Create minimal .zshrc - users can mount their own dotfiles for customization
COPY --chown=${USERNAME}:${USERNAME} zshrc /home/${USERNAME}/.zshrc
COPY --chown=${USERNAME}:${USERNAME} tmux.conf /home/${USERNAME}/.tmux.conf

# Copy firewall script, shell init, and utilities
# Files in /etc/agent-sandbox are root-owned to prevent agent tampering
COPY shell-init.sh /etc/agent-sandbox/shell-init.sh
COPY stacks/ /etc/agent-sandbox/stacks/
COPY init-firewall.sh /usr/local/bin/
COPY install-proxy-ca.sh /usr/local/bin/
COPY configure-apt-proxy.sh /usr/local/bin/
COPY link-dotfiles.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/

# System-level zshrc: sources shell-init.sh before ~/.zshrc so hooks survive
# custom dotfile mounts
COPY system-zshrc /etc/zsh/zshrc

USER root

# Git is built with prefix=/usr/local, so its system config lives here.
RUN mkdir -p /usr/local/etc
COPY system-gitconfig /usr/local/etc/gitconfig

RUN chmod 644 /etc/agent-sandbox/shell-init.sh /etc/zsh/zshrc /usr/local/etc/gitconfig && \
  chown root:root /etc/agent-sandbox/shell-init.sh && \
  chown root:root /etc/zsh/zshrc && \
  chown root:root /usr/local/etc/gitconfig && \
  chmod -R 755 /etc/agent-sandbox/stacks && \
  chown -R root:root /etc/agent-sandbox/stacks && \
  chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/install-proxy-ca.sh /usr/local/bin/configure-apt-proxy.sh /usr/local/bin/link-dotfiles.sh /usr/local/bin/entrypoint.sh && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/install-proxy-ca.sh, /usr/local/bin/configure-apt-proxy.sh" > /etc/sudoers.d/firewall && \
  chmod 0440 /etc/sudoers.d/firewall

# Create zshenv.d drop-in directory for PATH additions from stack scripts
# Append sourcing loop to /etc/zsh/zshenv
RUN mkdir -p /etc/zsh/zshenv.d && \
  printf '\n# Source drop-in environment files\nfor f in /etc/zsh/zshenv.d/*.zsh(N); do source "$f"; done\n' >> /etc/zsh/zshenv

# Install language stacks (optional, via STACKS build arg)
ARG STACKS=""
RUN if [ -n "$STACKS" ]; then \
      IFS=',' ; for stack in $STACKS; do \
        name="${stack%%:*}"; \
        version="${stack#*:}"; \
        [ "$name" = "$version" ] && version=""; \
        script="/etc/agent-sandbox/stacks/${name}.sh"; \
        if [ -f "$script" ]; then \
          "$script" $version; \
        else \
          echo "WARNING: Unknown stack: $name" >&2; \
        fi \
      done \
    fi

# Create .config directory owned by dev (for gh, etc.)
# Then create shell.d subdirectory owned by root (prevents agent from injecting malicious scripts)
RUN mkdir -p /home/${USERNAME}/.config && \
  chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.config && \
  mkdir -p /home/${USERNAME}/.config/agent-sandbox/shell.d && \
  chown root:root /home/${USERNAME}/.config/agent-sandbox && \
  chown root:root /home/${USERNAME}/.config/agent-sandbox/shell.d && \
  chmod 755 /home/${USERNAME}/.config/agent-sandbox /home/${USERNAME}/.config/agent-sandbox/shell.d

USER ${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [ "sleep", "infinity" ]
