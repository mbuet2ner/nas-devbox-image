#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-ubuntu}"
USER_HOME="/home/${USERNAME}"
SSH_KEY_STORE="${SSH_KEY_STORE:-/ssh-host-keys}"
AUTHORIZED_KEYS_CONTENT="${AUTHORIZED_KEYS:-}"

ensure_host_keys() {
  mkdir -p "${SSH_KEY_STORE}"

  shopt -s nullglob
  local persisted=("${SSH_KEY_STORE}"/ssh_host_*_key "${SSH_KEY_STORE}"/ssh_host_*_key.pub)
  shopt -u nullglob

  if [ "${#persisted[@]}" -eq 0 ]; then
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
    ssh-keygen -A
    cp /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub "${SSH_KEY_STORE}/"
  else
    cp "${SSH_KEY_STORE}"/ssh_host_*_key "${SSH_KEY_STORE}"/ssh_host_*_key.pub /etc/ssh/
  fi

  chmod 600 /etc/ssh/ssh_host_*_key
  chmod 644 /etc/ssh/ssh_host_*_key.pub
}

ensure_home_state() {
  mkdir -p "${USER_HOME}/.ssh" "${USER_HOME}/.config"
  touch "${USER_HOME}/.zsh_history"

  if [ -n "${AUTHORIZED_KEYS_CONTENT}" ] && [ ! -s "${USER_HOME}/.ssh/authorized_keys" ]; then
    printf '%s\n' "${AUTHORIZED_KEYS_CONTENT}" > "${USER_HOME}/.ssh/authorized_keys"
  fi

  if [ ! -f "${USER_HOME}/.zshrc" ]; then
    cat > "${USER_HOME}/.zshrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
EOF
  elif ! grep -q 'starship init zsh' "${USER_HOME}/.zshrc"; then
    cat >> "${USER_HOME}/.zshrc" <<'EOF'

export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
EOF
  fi

  if [ ! -f "${USER_HOME}/.bashrc" ]; then
    cat > "${USER_HOME}/.bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
  elif ! grep -q 'starship init bash' "${USER_HOME}/.bashrc"; then
    cat >> "${USER_HOME}/.bashrc" <<'EOF'

export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
EOF
  fi

  if [ ! -f "${USER_HOME}/.config/starship.toml" ]; then
    cat > "${USER_HOME}/.config/starship.toml" <<'EOF'
add_newline = false

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"
EOF
  fi

  chmod 700 "${USER_HOME}/.ssh"
  if [ -f "${USER_HOME}/.ssh/authorized_keys" ]; then
    chmod 600 "${USER_HOME}/.ssh/authorized_keys"
  fi

  chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}" /workspace
}

ensure_host_keys
ensure_home_state

exec "$@"
