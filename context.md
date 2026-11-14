# Omarchy sandbox

This is a headless Omarchy-on-Arch sandbox. It provides Omarchy's CLI and TUI
tools and configs on an Arch Linux userland. It is not a full Omarchy install:
there is no Hyprland desktop, no GPU, no systemd session, and no Limine/Btrfs
boot. Many `omarchy-*` desktop and hardware commands will fail. Docker
Sandboxes still boots Docker's microVM kernel; only the userland is Omarchy's.

You run as the non-root `agent` user (UID 1000, home `/home/agent`). The
workspace is `/home/agent/workspace`.

## Tools on PATH

`omarchy`, `omarchy-version`, `nvim` (LazyVim), `tmux`, `lazygit`, `starship`,
`git`, `fastfetch`, `yay`, and the following AI CLIs are installed:

- `codex` — OpenAI Codex CLI
- `claude` — Claude Code
- `opencode` — OpenCode
- `gemini` — Google Gemini CLI
- `copilot` — GitHub Copilot CLI

Use `/etc/sandbox-persistent.sh` for environment exports that later Bash
commands need (login, interactive, and non-interactive shells source it).
Keep shell completion scripts out of that file, because non-interactive
commands also source it via `BASH_ENV`.

Codex is installed as `codex`. Prefer launching it with
`sbx run codex --template omarchy-sandbox:4.5.0` so Docker Sandboxes can
manage OpenAI credentials on the host. If you are already in a shell
sandbox, run `codex` directly.
