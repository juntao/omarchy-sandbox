# Docker Sandboxes bash env (BASH_ENV, login, and interactive shells).
# Keep this file free of completion and interactive-only setup.
#
# BASH_ENV is sourced for every non-interactive bash, including the helper
# below, so this guard is required to avoid a fork loop.
if [[ -n "${OMARCHY_SANDBOX_ENV_SOURCED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
OMARCHY_SANDBOX_ENV_SOURCED=1
export OMARCHY_SANDBOX_ENV_SOURCED

/usr/local/bin/omarchy-sandbox-ensure-herdr >/dev/null 2>&1 || true
# shellcheck disable=SC1091
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh
