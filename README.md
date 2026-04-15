# NAS Devbox Image

This repository builds my slightly customized DevContainer for remote development. The container will runs on my NAS and I connect via SSH from my iPhone. DevContainers are chosen for convenience and extensability.
The Dockerfile is hardened using [OWASP recommendations](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html).

Ubuntu-based remote development container for OMV or any Docker host, with direct SSH access and a persistent home directory.

## What this image includes

- `openssh-server` on port `2222`
- non-root login user: `vscode`
- `zsh` as the login shell
- `starship` prompt auto-enabled for SSH logins
- `git`, `tmux`, `gh`, `ripgrep`, `fzf`, `bat`, `eza`, `zoxide`, `jq`
- `uv` for Python tooling
- `nodejs` and `npm`
- `codex` via `@openai/codex`
- `claude` via `@anthropic-ai/claude-code`
- scroll-friendly tmux defaults with mouse support, session titles, and clipboard integration
- default Codex notification wiring that publishes to `http://ntfy`

## Why Claude Code uses npm here

Anthropic currently recommends the native Linux installer, but that installs `claude` into `~/.local/bin`. Because this image intentionally persists all of `/home/vscode`, a fresh bind mount could hide that binary. This image uses the npm package instead so `claude` stays globally available from the image layer while your personal Claude config still persists in `/home/vscode`.

## Persistent paths

Mount these paths on the host:

- `/home/vscode`
- `/workspace`
- `/ssh-host-keys`

Persisting `/home/vscode` covers:

- `~/.ssh`
- `~/.gitconfig`
- `~/.config/gh`
- `~/.claude`
- `~/.tmux.conf`
- Codex config under your home directory
- `~/.zshrc`
- `~/.config/starship.toml`
- shell history

If `~/.tmux.conf` or `~/.codex/config.toml` are missing on first boot, the container seeds them with minimal tmux defaults for scrolling, session titles, clipboard integration, and the default Codex notification setup for `http://ntfy`.

Persisting `/ssh-host-keys` keeps the SSH server fingerprint stable across container recreation.

## Security defaults

- password SSH login disabled
- root SSH login disabled
- non-root remote login user
- no Docker socket mount
- `no-new-privileges:true`
- only `NET_RAW` dropped by default to avoid breaking `sshd`

## First-time SSH bootstrap

You can set `AUTHORIZED_KEYS` in Compose on first boot to seed `~/.ssh/authorized_keys`. After that, the persisted home directory keeps your SSH config and keys.

## Example Compose

See [docker-compose.example.yml](./docker-compose.example.yml).

The example binds SSH to `127.0.0.1:2222`. If you want LAN access, replace that with your NAS LAN IP or `2222:2222`.

## Build and publish with GitHub Actions

The workflow at `.github/workflows/publish.yml` publishes a multi-arch image to GHCR for `linux/amd64` and `linux/arm64`.

To use it:

1. Create a new GitHub repository and push this folder to it.
2. Ensure GitHub Actions is enabled for the repository.
3. Push to `main` or create a tag like `v1.0.0`.
4. Pull the resulting image from GHCR

## Local build

```bash
docker build -t nas-devbox-image:local .
```

## Notes

- The container process starts as `root` so `sshd` can launch, but interactive logins go to the unprivileged `vscode` user.
- `sudo` is intentionally not configured for the remote user.
