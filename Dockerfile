FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=vscode

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base tools for SSH access, shell UX, dev workflows, and Codex/Claude dependencies. bubblewrap for sandboxing
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

# Prompt and Python tooling.
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir /usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL=/usr/local/bin sh

# Prepare the runtime user and persistent mount points.
RUN usermod --shell /usr/bin/zsh "${USERNAME}" && \
    mkdir -p /workspace /var/run/sshd /ssh-host-keys && \
    chown -R "${USERNAME}:${USERNAME}" /workspace /ssh-host-keys /home/${USERNAME} && \
    passwd -l "${USERNAME}"

# Install AI CLIs globally
RUN npm install -g @openai/codex @anthropic-ai/claude-code

COPY scripts/entrypoint.sh /usr/local/bin/devbox-entrypoint
COPY ssh/10-devbox.conf /etc/ssh/sshd_config.d/10-devbox.conf

# This allows us to get notified when Codex is done or needs input
COPY defaults/.tmux.conf /usr/local/share/devbox-defaults/.tmux.conf
COPY defaults/codex-config.toml /usr/local/share/devbox-defaults/.codex/config.toml

# Keep runtime paths and shell defaults explicit.
ENV USERNAME=${USERNAME} \
    USER=${USERNAME} \
    HOME=/home/${USERNAME} \
    SHELL=/usr/bin/zsh \
    TERM=xterm-256color

WORKDIR /workspace

EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
