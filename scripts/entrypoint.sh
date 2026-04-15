#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-vscode}"
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

ensure_tmux_config() {
  local tmux_conf="${USER_HOME}/.tmux.conf"

  if [ ! -f "${tmux_conf}" ]; then
    cat > "${tmux_conf}" <<'TMUXEOF'
set -g bell-action any
set -g monitor-bell on

# Codex waiting for input -> BEL -> tmux -> ntfy
set-hook -g alert-bell 'run-shell "curl -fsS \
  -H \"Title: Codex needs input\" \
  -H \"Priority: urgent\" \
  -H \"Tags: warning,robot\" \
  -d \"session=#{session_name}\" \
  http://ntfy/up-codex-approval >/dev/null || true"'
TMUXEOF
  fi
}

ensure_codex_config() {
  local codex_dir="${USER_HOME}/.codex"
  local codex_conf="${codex_dir}/config.toml"

  mkdir -p "${codex_dir}"

  if [ ! -f "${codex_conf}" ]; then
    cat > "${codex_conf}" <<'CODEXEOF'
[tui]
# Only notify when Codex needs input
notifications = ["approval-requested"]
notification_method = "bel"

# Codex finished -> ntfy
notify = ["sh", "-c", "curl -fsS -H \"Title: Codex done\" -H \"Priority: default\" -H \"Tags: white_check_mark,robot\" -d \"Codex finished a turn\" http://ntfy/up-codex-done >/dev/null || true"]
CODEXEOF
  fi
}

ensure_home_state() {
  mkdir -p "${USER_HOME}/.ssh" "${USER_HOME}/.config"
  touch "${USER_HOME}/.zsh_history"

  if [ -n "${AUTHORIZED_KEYS_CONTENT}" ] && [ ! -s "${USER_HOME}/.ssh/authorized_keys" ]; then
    printf '%s\n' "${AUTHORIZED_KEYS_CONTENT}" > "${USER_HOME}/.ssh/authorized_keys"
  fi

  if [ ! -f "${USER_HOME}/.zshrc" ]; then
    cat > "${USER_HOME}/.zshrc" <<'ZSHEOF'
export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
ZSHEOF
  elif ! grep -q 'starship init zsh' "${USER_HOME}/.zshrc"; then
    cat >> "${USER_HOME}/.zshrc" <<'ZSHEOF'

export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
ZSHEOF
  fi

  if [ ! -f "${USER_HOME}/.bashrc" ]; then
    cat > "${USER_HOME}/.bashrc" <<'BASHEOF'
export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
BASHEOF
  elif ! grep -q 'starship init bash' "${USER_HOME}/.bashrc"; then
    cat >> "${USER_HOME}/.bashrc" <<'BASHEOF'

export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
BASHEOF
  fi

  if [ ! -f "${USER_HOME}/.config/starship.toml" ]; then
    cat > "${USER_HOME}/.config/starship.toml" <<'STARSHIPEOF'
add_newline = false

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"
STARSHIPEOF
  fi

  ensure_tmux_config
  ensure_codex_config

  chmod 700 "${USER_HOME}/.ssh"
  if [ -f "${USER_HOME}/.ssh/authorized_keys" ]; then
    chmod 600 "${USER_HOME}/.ssh/authorized_keys"
  fi

  chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}" /workspace
}

ensure_runtime_dirs() {
  mkdir -p /run/sshd /var/run/sshd
}

ensure_host_keys
ensure_runtime_dirs
ensure_home_state

exec "$@"
