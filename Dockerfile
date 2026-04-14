FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=vscode

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    zsh \
    git \
    tmux \
    gh \
    nodejs \
    npm \
    ripgrep \
    fzf \
    bat \
    eza \
    zoxide \
    jq \
    curl \
    ca-certificates \
    unzip \
    less \
    procps \
    iproute2 \
    dnsutils \
    bubblewrap \
    build-essential \
    locales && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir /usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL=/usr/local/bin sh

RUN usermod --shell /usr/bin/zsh "${USERNAME}" && \
    mkdir -p /workspace /var/run/sshd /ssh-host-keys && \
    chown -R "${USERNAME}:${USERNAME}" /workspace /ssh-host-keys /home/${USERNAME} && \
    passwd -l "${USERNAME}"

RUN npm install -g @openai/codex @anthropic-ai/claude-code && \
    npm cache clean --force && \
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then ln -s /usr/bin/batcat /usr/local/bin/bat; fi

COPY scripts/entrypoint.sh /usr/local/bin/devbox-entrypoint
COPY ssh/10-devbox.conf /etc/ssh/sshd_config.d/10-devbox.conf

RUN chmod 755 /usr/local/bin/devbox-entrypoint

ENV USERNAME=${USERNAME} \
    USER=${USERNAME} \
    HOME=/home/${USERNAME} \
    SHELL=/usr/bin/zsh \
    TERM=xterm-256color

WORKDIR /workspace

EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
