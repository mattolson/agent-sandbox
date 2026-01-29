FROM debian:bookworm

ARG TZ
ENV TZ="$TZ"

# Install basic development tools and firewall dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  curl \
  wget \
  ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up non-root user
ARG USERNAME=dev
RUN groupadd --system --gid 500 ${USERNAME} && useradd --system --create-home --uid 500 --gid 500 ${USERNAME}

# Persist shell history (docker volume)
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history /commandhistory/.zsh_history \
  && chown -R ${USERNAME} /commandhistory

# Set environment variables
ENV DEVCONTAINER=true

# Create workspace and config directories
RUN mkdir -p /workspace && chown -R ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

USER ${USERNAME}

# Set default shell and editor
ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim

# Create minimal .zshrc - users can mount their own dotfiles for customization
COPY --chown=${USERNAME}:${USERNAME} zshrc /home/${USERNAME}/.zshrc

# Configure git to use HTTPS instead of SSH (port 22 is blocked to prevent tunneling)
RUN git config --global url."https://github.com/".insteadOf git@github.com: && \
  git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/

# Copy firewall script and shell init
# Files in /etc/agent-sandbox are root-owned to prevent agent tampering
COPY shell-init.sh /etc/agent-sandbox/shell-init.sh
COPY init-firewall.sh /usr/local/bin/
COPY install-proxy-ca.sh /usr/local/bin/
COPY configure-apt-proxy.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
USER root
RUN chmod 644 /etc/agent-sandbox/shell-init.sh && \
  chown root:root /etc/agent-sandbox/shell-init.sh && \
  chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/install-proxy-ca.sh /usr/local/bin/configure-apt-proxy.sh /usr/local/bin/entrypoint.sh && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/install-proxy-ca.sh, /usr/local/bin/configure-apt-proxy.sh" > /etc/sudoers.d/firewall && \
  chmod 0440 /etc/sudoers.d/firewall

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
CMD ["zsh"]
