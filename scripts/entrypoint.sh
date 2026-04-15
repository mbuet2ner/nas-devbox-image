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
    return
  fi

  python3 - "${tmux_conf}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
desired = """set -g bell-action any
set -g monitor-bell on

# Codex waiting for input -> BEL -> tmux -> ntfy
set-hook -g alert-bell 'run-shell \"curl -fsS \\
  -H \\\"Title: Codex needs input\\\" \\
  -H \\\"Priority: urgent\\\" \\
  -H \\\"Tags: warning,robot\\\" \\
  -d \\\"session=#{session_name}\\\" \\
  http://ntfy/up-codex-approval >/dev/null || true\"'
"""
legacy_blocks = [
    """set -g bell-action any
set -g monitor-bell on

# Codex waiting for input -> BEL -> tmux -> ntfy
set-hook -g alert-bell 'run-shell \"curl -fsS \\
  -H \\\"Authorization: Bearer $NTFY_TOKEN\\\" \\
  -H \\\"Title: Codex needs input\\\" \\
  -H \\\"Priority: urgent\\\" \\
  -H \\\"Tags: warning,robot\\\" \\
  -d \\\"session=#{session_name}\\\" \\
  ${NTFY_BASE_URL}/up-codex-approval >/dev/null || true\"'
""",
    """set -g bell-action any
set -g monitor-bell on
set -ag update-environment " NTFY_BASE_URL NTFY_TOKEN"

# Codex waiting for input -> BEL -> tmux -> ntfy
set-hook -g alert-bell 'run-shell \"curl -fsS \\
  -H \\\"Authorization: Bearer #{environ:NTFY_TOKEN}\\\" \\
  -H \\\"Title: Codex needs input\\\" \\
  -H \\\"Priority: urgent\\\" \\
  -H \\\"Tags: warning,robot\\\" \\
  -d \\\"session=#{session_name}\\\" \\
  #{environ:NTFY_BASE_URL}/up-codex-approval >/dev/null || true\"'
""",
]
updated = text
for block in legacy_blocks:
    updated = updated.replace(block, desired)
updated = updated.replace('set -ag update-environment " NTFY_BASE_URL NTFY_TOKEN"\n', '')
updated = updated.replace('  -H \\\"Authorization: Bearer $NTFY_TOKEN\\\" \\\n', '')
updated = updated.replace('  -H \\\"Authorization: Bearer #{environ:NTFY_TOKEN}\\\" \\\n', '')
updated = updated.replace('${NTFY_BASE_URL}/up-codex-approval', 'http://ntfy/up-codex-approval')
updated = updated.replace('#{environ:NTFY_BASE_URL}/up-codex-approval', 'http://ntfy/up-codex-approval')
if updated != text:
    path.write_text(updated)
PY
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
    return
  fi

  python3 - "${codex_conf}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
desired_lines = [
    '# Only notify when Codex needs input',
    'notifications = ["approval-requested"]',
    'notification_method = "bel"',
    '',
    '# Codex finished -> ntfy',
    'notify = ["sh", "-c", "curl -fsS -H \\\"Title: Codex done\\\" -H \\\"Priority: default\\\" -H \\\"Tags: white_check_mark,robot\\\" -d \\\"Codex finished a turn\\\" http://ntfy/up-codex-done >/dev/null || true"]',
]
lines = text.splitlines()
section_re = re.compile(r'^\s*\[(.+)\]\s*$')
start = end = None
for idx, line in enumerate(lines):
    match = section_re.match(line)
    if not match:
        continue
    if match.group(1) == 'tui':
        start = idx
        end = len(lines)
        for j in range(idx + 1, len(lines)):
            if section_re.match(lines[j]):
                end = j
                break
        break

if start is None:
    if lines and lines[-1] != '':
        lines.append('')
    lines.append('[tui]')
    lines.extend(desired_lines)
else:
    preserved = []
    for line in lines[start + 1:end]:
        stripped = line.strip()
        if stripped in {
            '# Only notify when Codex needs input',
            '# Codex finished -> ntfy',
        }:
            continue
        if stripped.startswith('notifications ='):
            continue
        if stripped.startswith('notification_method ='):
            continue
        if stripped.startswith('notify ='):
            continue
        if 'Authorization: Bearer $NTFY_TOKEN' in line:
            continue
        if '${NTFY_BASE_URL}/up-codex-done' in line:
            continue
        preserved.append(line)

    new_section = ['[tui]'] + desired_lines
    if preserved:
        if new_section[-1] != '':
            new_section.append('')
        new_section.extend(preserved)
    lines = lines[:start] + new_section + lines[end:]

updated = '\n'.join(lines).rstrip() + '\n'
if updated != text:
    path.write_text(updated)
PY
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
