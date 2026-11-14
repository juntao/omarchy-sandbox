#!/bin/bash
# Install Google Chrome, agent-browser, and chrome-devtools-mcp (plus the
# chrome-devtools CLI). Point the tools at the image's Chrome, register
# the MCP server for Claude Code, Codex, and Gemini, and copy the
# DevTools skills. Run as user agent during the image build, before
# ENV BASH_ENV is set.
set -euo pipefail
unset BASH_ENV || true
export OMARCHY_SANDBOX_SKIP_HERDR=1

AGENT_HOME=/home/agent
CHROME_WRAPPER=/usr/local/bin/google-chrome-stable

# The Herdr install adds [omarchy] to pacman.conf but does not sync its
# database (to avoid pacman-key stalls). yay then fails with "could not
# find database" when installing official repo deps such as gtk3. Sync
# first; if the omarchy db is still missing, drop that section so the
# official repos can be used.
if grep -q '^\[omarchy\]' /etc/pacman.conf && [ ! -e /var/lib/pacman/sync/omarchy.db ]; then
  sudo pacman -Sy --noconfirm || true
fi
if grep -q '^\[omarchy\]' /etc/pacman.conf && [ ! -e /var/lib/pacman/sync/omarchy.db ]; then
  sudo python3 - <<'ENDCONF'
from pathlib import Path
p = Path("/etc/pacman.conf")
out, skip = [], False
for line in p.read_text().splitlines(True):
    if line.startswith("[omarchy]"):
        skip = True
        continue
    if skip and line.startswith("["):
        skip = False
    if not skip:
        out.append(line)
p.write_text("".join(out))
ENDCONF
fi

# Fonts come from official repos. Build google-chrome from the AUR
# (official Google .deb) with makepkg. After pacman -Sy, the omarchy
# repo also ships google-chrome, and yay prefers that package even with
# --aur, but its signature is "unknown trust" here because pacman-key
# is not fully initialized in the image.
sudo pacman -S --noconfirm --needed ttf-liberation ttf-dejavu
git clone --depth 1 https://aur.archlinux.org/google-chrome.git /tmp/google-chrome-aur
( cd /tmp/google-chrome-aur && makepkg -si --noconfirm )
rm -rf /tmp/google-chrome-aur

sudo npm install -g chrome-devtools-mcp agent-browser

sudo install -m 0755 /tmp/google-chrome-sandbox-wrapper "$CHROME_WRAPPER"
sudo ln -sfn google-chrome-stable /usr/local/bin/google-chrome
command -v google-chrome-stable >/dev/null
test -x /opt/google/chrome/google-chrome || test -x /usr/bin/google-chrome-stable
command -v chrome-devtools >/dev/null
command -v chrome-devtools-mcp >/dev/null
command -v agent-browser >/dev/null

install -d -m 0755 "$AGENT_HOME/.config/cd4a"
cat > "$AGENT_HOME/.config/cd4a/config.json" << 'JSON'
{
  "headless": true,
  "isolated": true,
  "executablePath": "/usr/local/bin/google-chrome-stable",
  "chromeArg": ["--no-sandbox", "--disable-dev-shm-usage"],
  "usageStatistics": false
}
JSON

MCP_ARGS_JSON='["--headless=true", "--isolated=true", "--executablePath=/usr/local/bin/google-chrome-stable", "--chromeArg=--no-sandbox", "--chromeArg=--disable-dev-shm-usage", "--no-usage-statistics"]'

# Claude Code user scope lives in ~/.claude.json.
if [ -f "$AGENT_HOME/.claude.json" ]; then
  tmp=$(mktemp)
  jq --argjson args "$MCP_ARGS_JSON" \
    '.mcpServers["chrome-devtools"] = {command: "chrome-devtools-mcp", args: $args}' \
    "$AGENT_HOME/.claude.json" > "$tmp"
  install -m 0644 "$tmp" "$AGENT_HOME/.claude.json"
  rm -f "$tmp"
else
  jq -n --argjson args "$MCP_ARGS_JSON" \
    '{mcpServers: {"chrome-devtools": {command: "chrome-devtools-mcp", args: $args}}}' \
    > "$AGENT_HOME/.claude.json"
  chmod 0644 "$AGENT_HOME/.claude.json"
fi

# Codex: append an MCP server block without wiping a later first-run config.
install -d -m 0755 "$AGENT_HOME/.codex"
if [ ! -f "$AGENT_HOME/.codex/config.toml" ] || ! grep -q '^\[mcp_servers\.chrome-devtools\]' "$AGENT_HOME/.codex/config.toml"; then
  cat >> "$AGENT_HOME/.codex/config.toml" << 'TOML'

[mcp_servers.chrome-devtools]
command = "chrome-devtools-mcp"
args = ["--headless=true", "--isolated=true", "--executablePath=/usr/local/bin/google-chrome-stable", "--chromeArg=--no-sandbox", "--chromeArg=--disable-dev-shm-usage", "--no-usage-statistics"]
TOML
fi

install -d -m 0755 "$AGENT_HOME/.gemini"
if [ -f "$AGENT_HOME/.gemini/settings.json" ]; then
  tmp=$(mktemp)
  jq --argjson args "$MCP_ARGS_JSON" \
    '.mcpServers["chrome-devtools"] = {command: "chrome-devtools-mcp", args: $args}' \
    "$AGENT_HOME/.gemini/settings.json" > "$tmp"
  install -m 0644 "$tmp" "$AGENT_HOME/.gemini/settings.json"
  rm -f "$tmp"
else
  jq -n --argjson args "$MCP_ARGS_JSON" \
    '{mcpServers: {"chrome-devtools": {command: "chrome-devtools-mcp", args: $args}}}' \
    > "$AGENT_HOME/.gemini/settings.json"
  chmod 0644 "$AGENT_HOME/.gemini/settings.json"
fi

skills_src="$(npm root -g)/chrome-devtools-mcp/skills"
if [ -d "$skills_src" ]; then
  for dest in "$AGENT_HOME/.claude/skills" "$AGENT_HOME/.codex/skills" "$AGENT_HOME/.gemini/skills"; do
    install -d -m 0755 "$dest"
    cp -R "$skills_src"/. "$dest/"
  done
fi

for path in \
  "$AGENT_HOME/.config/cd4a" \
  "$AGENT_HOME/.claude.json" \
  "$AGENT_HOME/.claude" \
  "$AGENT_HOME/.codex" \
  "$AGENT_HOME/.gemini"
do
  [ -e "$path" ] && chown -R agent:agent "$path"
done

rm -rf "$AGENT_HOME/.cache"
sudo npm cache clean --force
sudo pacman -Scc --noconfirm
sudo rm -rf /var/cache/pacman/pkg/* /root/.npm /root/.cache /tmp/*
