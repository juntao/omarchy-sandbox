# Omarchy sandbox

This is a headless Omarchy-on-Arch sandbox, intended as an **agent OS**.
It provides Omarchy's CLI and TUI tools and configs on an Arch Linux
userland so coding agents can work here. It is not a full Omarchy install:
there is no Hyprland desktop, no GPU, no systemd session, and no Limine/Btrfs
boot. Many `omarchy-*` desktop and hardware commands will fail. Docker
Sandboxes still boots Docker's microVM kernel; only the userland is Omarchy's.

You run as the non-root `agent` user (UID 1000, home `/home/agent`). The
workspace is `/home/agent/workspace`.

## Tools on PATH

`omarchy`, `omarchy-version`, `nvim` (LazyVim), `tmux`, `herdr`, `lazygit`,
`starship`, `git`, `fastfetch`, `yay`, and the following AI CLIs are installed:

- `codex` — OpenAI Codex CLI
- `claude` — Claude Code
- `opencode` — OpenCode
- `gemini` — Google Gemini CLI
- `copilot` — GitHub Copilot CLI

A headless `herdr server` is started automatically with the shell (socket
`~/.config/herdr/herdr.sock`). Use `herdr status`, `herdr session list`,
`herdr agent list`, `herdr agent start`, and `herdr --skill`. Attach to the
persistent session with `herdr` when you have a TTY. Tmux is also configured
with Omarchy's `tmux.conf` (prefix `Ctrl + Space`). Super keybindings from
the Omarchy desktop are not available.

Use `/etc/sandbox-persistent.sh` for environment exports that later Bash
commands need. Login, interactive, and non-interactive shells source it
through `/etc/sandbox-env.sh`. Keep shell completion scripts out of those
files, because non-interactive commands also source them via `BASH_ENV`.
Set `OMARCHY_SANDBOX_SKIP_HERDR=1` if you do not want the Herdr server
auto-started.

Codex is installed as `codex`. Prefer launching it with
`sbx run codex --template omarchy-sandbox:4.5.0` so Docker Sandboxes can
manage OpenAI credentials on the host. If you are already in a shell
sandbox, run `codex` directly.
