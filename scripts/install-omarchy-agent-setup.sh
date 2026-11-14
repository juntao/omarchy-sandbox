#!/bin/bash
# Per-user Omarchy setup that applies without the desktop, following
# upstream omarchy-provision-user and install/user/mise.sh:
#   - link Omarchy's `omarchy` agent skill into each agent harness
#   - install Omarchy's system mise config so its default tools (gh, uv,
#     and other CLIs) are lazily installed on first use
# Run as user agent during the image build, before ENV BASH_ENV is set.
set -euo pipefail
unset BASH_ENV || true
export OMARCHY_SANDBOX_SKIP_HERDR=1

AGENT_HOME=/home/agent
OMARCHY_PATH="${OMARCHY_PATH:-$AGENT_HOME/.local/share/omarchy}"

# Upstream links every skill in default/agents/skills. Only `omarchy` is
# linked here: `omarchy-app` scaffolds Qt desktop apps and `diagnose-crash`
# reads systemd-coredump, and neither exists in this image.
# ~/.gemini/skills is added because the Chrome DevTools skills live there.
skill="$OMARCHY_PATH/default/agents/skills/omarchy"
test -r "$skill/SKILL.md"
for dir in \
  "$AGENT_HOME/.agents/skills" \
  "$AGENT_HOME/.claude/skills" \
  "$AGENT_HOME/.codex/skills" \
  "$AGENT_HOME/.gemini/skills" \
  "$AGENT_HOME/.gemini/config/skills" \
  "$AGENT_HOME/.pi/agent/skills"
do
  mkdir -p "$dir"
  ln -sfn "$skill" "$dir/omarchy"
done

# Omarchy's system mise config. The tool list leaves out the agent CLIs
# and Node that the image already installs system-wide, so `claude`,
# `codex`, `opencode`, `copilot`, and `node` keep resolving to those
# copies in interactive shells (mise activate puts its shims first).
# omarchy-agent-accounts.toml is not installed: it routes claude and codex
# through Omarchy's subscription switcher.
conf_src="$OMARCHY_PATH/etc/mise/conf.d"
sudo install -d -m 0755 /etc/mise/conf.d
sudo install -m 0644 "$conf_src/omarchy.toml" /etc/mise/conf.d/omarchy.toml
tmp=$(mktemp)
grep -v -E '^(claude|codex|opencode|copilot|node) = ' "$conf_src/omarchy-tools.toml" > "$tmp"
sudo install -m 0644 "$tmp" /etc/mise/conf.d/omarchy-tools.toml
rm -f "$tmp"

# Same as install/user/mise.sh: build the lazy shims without resolving
# versions over the network.
MISE_OFFLINE=true mise reshim --system 2>/dev/null
MISE_OFFLINE=true mise reshim 2>/dev/null
test -x "$AGENT_HOME/.local/share/mise/shims/gh"
test -x "$AGENT_HOME/.local/share/mise/shims/uv"
test ! -e "$AGENT_HOME/.local/share/mise/shims/claude"

rm -rf "$AGENT_HOME/.cache" /tmp/mise* 2>/dev/null || true
