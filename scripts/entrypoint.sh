#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-vscode}"
USER_HOME="/home/${USERNAME}"
SSH_KEY_STORE="${SSH_KEY_STORE:-/ssh-host-keys}"
AUTHORIZED_KEYS_CONTENT="${AUTHORIZED_KEYS:-}"
DEFAULTS_DIR="/usr/local/share/devbox-defaults"

# Ensure runtime dirs exist (sshd + persisted key storage)
ensure_runtime_dirs() {
  mkdir -p /run/sshd /var/run/sshd "${SSH_KEY_STORE}"
}

# Persist SSH host keys across container restarts (avoid MITM warnings)
ensure_host_keys() {
  shopt -s nullglob
  local persisted=("${SSH_KEY_STORE}"/ssh_host_*_key)
  shopt -u nullglob

  if [ "${#persisted[@]}" -eq 0 ]; then
    # First run: generate keys and persist them
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
    ssh-keygen -A
    cp /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub "${SSH_KEY_STORE}/"
  else
    # Subsequent runs: restore persisted keys
    cp "${SSH_KEY_STORE}"/ssh_host_*_key "${SSH_KEY_STORE}"/ssh_host_*_key.pub /etc/ssh/
  fi

  chmod 600 /etc/ssh/ssh_host_*_key
  chmod 644 /etc/ssh/ssh_host_*_key.pub
}

# Write file only if it does not exist (preserve user changes)
write_if_missing() {
  local path="$1"
  local content="$2"
  [ -f "$path" ] || printf '%s\n' "$content" > "$path"
}

# Append config block only if marker is missing (idempotent setup)
append_if_missing() {
  local path="$1"
  local marker="$2"
  local content="$3"

  if [ ! -f "$path" ]; then
    printf '%s\n' "$content" > "$path"
  elif ! grep -qF "$marker" "$path"; then
    printf '\n%s\n' "$content" >> "$path"
  fi
}

# Copy defaults from image only once (home is bind-mounted, so image files are hidden)
copy_if_missing() {
  local src="$1"
  local dst="$2"
  [ -f "$dst" ] || cp "$src" "$dst"
}

# Initialize user home with minimal defaults and persisted state
ensure_home_state() {
  mkdir -p \
    "${USER_HOME}/.ssh" \
    "${USER_HOME}/.config" \
    "${USER_HOME}/.codex"

  # Ensure shell history persists
  touch "${USER_HOME}/.zsh_history"

  # Install authorized_keys once (for SSH login)
  if [ -n "${AUTHORIZED_KEYS_CONTENT}" ] && [ ! -s "${USER_HOME}/.ssh/authorized_keys" ]; then
    printf '%s\n' "${AUTHORIZED_KEYS_CONTENT}" > "${USER_HOME}/.ssh/authorized_keys"
  fi

  # Ensure zsh has starship + zoxide (nice shell UX)
  append_if_missing "${USER_HOME}/.zshrc" 'starship init zsh' \
'export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi'

  # Ensure bash has starship (fallback shell)
  append_if_missing "${USER_HOME}/.bashrc" 'starship init bash' \
'export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi'

  # Default starship config (simple prompt)
  write_if_missing "${USER_HOME}/.config/starship.toml" \
'add_newline = false

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"'

  # Seed Codex/tmux defaults:
  # - tmux: basic bell settings only
  # - codex: sends ntfy on completion via notify hook
  copy_if_missing "${DEFAULTS_DIR}/.tmux.conf" "${USER_HOME}/.tmux.conf"
  copy_if_missing "${DEFAULTS_DIR}/.codex/config.toml" "${USER_HOME}/.codex/config.toml"

  # Fix permissions for SSH
  chmod 700 "${USER_HOME}/.ssh"
  [ ! -f "${USER_HOME}/.ssh/authorized_keys" ] || chmod 600 "${USER_HOME}/.ssh/authorized_keys"

  # Ensure correct ownership (mounted volumes may have wrong owner)
  chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}" /workspace
}

ensure_runtime_dirs
ensure_host_keys
ensure_home_state

exec "$@"
