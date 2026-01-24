FROM debian:bookworm

ARG TZ
ENV TZ="$TZ"

# Install basic development tools, firewall dependencies, and yq for policy parsing
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

# Install yq for YAML parsing
ARG YQ_VERSION=v4.44.1
RUN ARCH=$(dpkg --print-architecture) && \
  wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" && \
  chmod +x /usr/local/bin/yq

# Set up non-root user
ARG USERNAME=dev
RUN groupadd --system --gid 500 ${USERNAME} && useradd --system --create-home --uid 500 --gid 500 ${USERNAME}

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R ${USERNAME} /commandhistory

# Set environment variables
ENV DEVCONTAINER=true

# Create workspace and config directories
RUN mkdir -p /workspace && chown -R ${USERNAME}:${USERNAME} /workspace

WORKDIR /workspace

# Install git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER ${USERNAME}

# Set default shell and editor
ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim

# Install zsh with powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Copy default network policy, firewall script, and shell init
# All in /etc/agent-sandbox are root-owned to prevent agent tampering
COPY policy.yaml /etc/agent-sandbox/policy.yaml
COPY shell-init.sh /etc/agent-sandbox/shell-init.sh
COPY init-firewall.sh /usr/local/bin/
COPY install-proxy-ca.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
USER root
RUN chmod 644 /etc/agent-sandbox/policy.yaml /etc/agent-sandbox/shell-init.sh && \
  chown root:root /etc/agent-sandbox/policy.yaml /etc/agent-sandbox/shell-init.sh && \
  chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/install-proxy-ca.sh /usr/local/bin/entrypoint.sh && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/install-proxy-ca.sh" > /etc/sudoers.d/firewall && \
  chmod 0440 /etc/sudoers.d/firewall

# Create shell.d directory (root-owned to prevent agent from injecting malicious scripts)
# Users mount their customizations here; the mount overlays this empty directory
RUN mkdir -p /home/${USERNAME}/.config/agent-sandbox/shell.d && \
  chown root:root /home/${USERNAME}/.config/agent-sandbox/shell.d && \
  chmod 755 /home/${USERNAME}/.config/agent-sandbox/shell.d

USER ${USERNAME}

# Add shell initialization hook to zshrc
RUN echo '' >> ~/.zshrc && \
  echo '# Agent Sandbox shell initialization' >> ~/.zshrc && \
  echo 'source /etc/agent-sandbox/shell-init.sh' >> ~/.zshrc

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh"]
