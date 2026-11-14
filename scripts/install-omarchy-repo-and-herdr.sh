#!/bin/bash
# Add the official Omarchy pacman repo, install Herdr from verified packages,
# and copy Omarchy's Herdr config into the agent home.
#
# pacman-key --init can stall for a long time in a Docker build (no entropy),
# so Herdr is installed from local files whose SHA-256 is taken from the
# official repo database. The signing key is imported afterward, with a
# timeout, so a missing master key never blocks the build.
set -euo pipefail

OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
AGENT_HOME=/home/agent
OMARCHY_PATH="${OMARCHY_PATH:-$AGENT_HOME/.local/share/omarchy}"
ARCH=$(uname -m)
REPO="https://pkgs.omarchy.org/stable/${ARCH}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

add_omarchy_repo() {
  local sig_level=$1
  local tmp=/tmp/pacman.conf.new
  # Drop any existing [omarchy] section, then insert a fresh one before [core].
  awk '
    BEGIN { skip=0 }
    /^\[omarchy\]/ { skip=1; next }
    skip && /^\[/ { skip=0 }
    skip { next }
    { print }
  ' /etc/pacman.conf > "$tmp.base"
  awk -v sig="$sig_level" '
    /^\[core\]/ && !done {
      print "[omarchy]"
      print "SigLevel = " sig
      print "Server = https://pkgs.omarchy.org/stable/$arch"
      print ""
      done=1
    }
    { print }
  ' "$tmp.base" > "$tmp"
  if ! grep -q '^\[omarchy\]' "$tmp"; then
    printf '\n[omarchy]\nSigLevel = %s\nServer = https://pkgs.omarchy.org/stable/$arch\n' "$sig_level" >> "$tmp"
  fi
  install -m 0644 "$tmp" /etc/pacman.conf
  rm -f "$tmp" "$tmp.base"
}

desc_field() {
  local desc=$1 field=$2
  awk -v f="%$field%" '
    $0 == f { getline; print; exit }
  ' "$desc"
}

install_from_repo_db() {
  curl -fsSL -o "$WORKDIR/omarchy.db" "$REPO/omarchy.db"
  mkdir -p "$WORKDIR/db"
  zstd -d -c "$WORKDIR/omarchy.db" | tar -xf - -C "$WORKDIR/db"

  local name desc pkgdir filename sha256
  for name in omarchy-keyring herdr; do
    desc=""
    for pkgdir in "$WORKDIR/db"/${name}-*; do
      [ -f "$pkgdir/desc" ] || continue
      if [ "$(desc_field "$pkgdir/desc" NAME)" = "$name" ]; then
        desc="$pkgdir/desc"
        break
      fi
    done
    [ -n "$desc" ] || { echo "error: $name not found in $REPO/omarchy.db" >&2; return 1; }
    filename=$(desc_field "$desc" FILENAME)
    sha256=$(desc_field "$desc" SHA256SUM)
    curl -fsSL -o "$WORKDIR/$filename" "$REPO/$filename"
    echo "$sha256  $WORKDIR/$filename" | sha256sum -c -
    pacman -U --noconfirm "$WORKDIR/$filename"
  done
}

try_trust_omarchy_key() {
  # Best-effort: a signed repo is nicer for later updates, but Herdr is
  # already installed if this fails.
  if ! command -v timeout >/dev/null; then
    return 1
  fi
  if ! gpg --homedir /etc/pacman.d/gnupg --list-secret-keys >/dev/null 2>&1; then
    timeout 20 pacman-key --init || return 1
  fi
  if pacman-key --list-keys "$OMARCHY_KEY" >/dev/null 2>&1; then
    return 0
  fi
  timeout 20 curl -fsSL "https://keys.openpgp.org/vks/v1/by-fingerprint/${OMARCHY_KEY}" \
    | pacman-key --add - || return 1
  printf 'y\n' | timeout 20 pacman-key --lsign-key "$OMARCHY_KEY" || return 1
  return 0
}

install_from_repo_db

if try_trust_omarchy_key; then
  add_omarchy_repo "Required DatabaseOptional"
else
  echo "warning: could not initialize pacman keys; leaving [omarchy] with optional signatures" >&2
  add_omarchy_repo "Optional DatabaseOptional"
fi

pacman -Scc --noconfirm

mkdir -p "$AGENT_HOME/.config"
if [ -d "$OMARCHY_PATH/config/herdr" ]; then
  cp -a "$OMARCHY_PATH/config/herdr" "$AGENT_HOME/.config/"
  chown -R agent:agent "$AGENT_HOME/.config/herdr"
fi
