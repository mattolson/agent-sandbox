FROM debian:bookworm

ARG TZ
ENV TZ="$TZ"

# Install basic development tools, firewall dependencies
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
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
  python3 \
  neovim \
  curl \
  wget \
  ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Copy default network policy and firewall script
COPY policy.json /etc/agent-sandbox/policy.json
COPY init-firewall.py /usr/local/bin/
USER root
RUN chmod 644 /etc/agent-sandbox/policy.json && \
  chmod +x /usr/local/bin/init-firewall.py && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.py" > /etc/sudoers.d/firewall && \
  chmod 0440 /etc/sudoers.d/firewall

# Copy and set up entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
USER ${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh"]
