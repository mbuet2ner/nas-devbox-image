FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

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
    build-essential \
    locales && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir /usr/local/bin

RUN if id ubuntu >/dev/null 2>&1 && [ "${USER_UID}" = "1000" ] && [ "${USER_GID}" = "1000" ]; then \
        usermod -l "${USERNAME}" ubuntu && \
        groupmod -n "${USERNAME}" ubuntu && \
        usermod -d "/home/${USERNAME}" -m "${USERNAME}" && \
        chsh -s /usr/bin/zsh "${USERNAME}"; \
    elif ! id "${USERNAME}" >/dev/null 2>&1; then \
        groupadd --gid "${USER_GID}" "${USERNAME}" && \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /usr/bin/zsh "${USERNAME}"; \
    fi && \
    mkdir -p /workspace /var/run/sshd /ssh-host-keys /home/${USERNAME}/.config && \
    chown -R "${USERNAME}:${USERNAME}" /workspace /ssh-host-keys /home/${USERNAME} && \
    passwd -l "${USERNAME}" && \
    find /etc/sudoers.d -maxdepth 1 -type f \( -name '*ubuntu*' -o -name '*vscode*' -o -name '90-cloud-init-users' \) -delete || true && \
    gpasswd -d "${USERNAME}" sudo || true

RUN npm install -g @openai/codex @anthropic-ai/claude-code && \
    npm cache clean --force && \
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then ln -s /usr/bin/batcat /usr/local/bin/bat; fi

COPY scripts/entrypoint.sh /usr/local/bin/devbox-entrypoint

RUN chmod 755 /usr/local/bin/devbox-entrypoint && \
    mkdir -p /etc/ssh/sshd_config.d && \
    printf '%s\n' \
        'Port 2222' \
        'Protocol 2' \
        'PermitRootLogin no' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'ChallengeResponseAuthentication no' \
        'PubkeyAuthentication yes' \
        "AllowUsers ${USERNAME}" \
        'UsePAM yes' \
        'X11Forwarding no' \
        'AllowTcpForwarding yes' \
        'AllowAgentForwarding yes' \
        'PrintMotd no' \
        'ClientAliveInterval 120' \
        'ClientAliveCountMax 2' \
        'AuthorizedKeysFile .ssh/authorized_keys' \
        > /etc/ssh/sshd_config.d/10-devbox.conf

ENV USERNAME=${USERNAME} \
    USER=${USERNAME} \
    HOME=/home/${USERNAME} \
    SHELL=/usr/bin/zsh \
    TERM=xterm-256color

WORKDIR /workspace

EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
