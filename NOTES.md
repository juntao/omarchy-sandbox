# Changes versus upstream devmarchy

Upstream: https://github.com/ThatBlokeJosh/devmarchy (defaults to Omarchy v3.8.1).

Built here against Omarchy v4.5.0 (commit ac2690cd7be4f47e4a255f5e2e78d904d436b068).

Fixes applied:

1. **fastfetch config path (v4.x).** Omarchy 4.x moved the config from
   `config/fastfetch` to `etc/fastfetch`. The standalone Dockerfile copies
   whichever location exists.

2. **User account.** Upstream uses `devmarchy` with home `/home/devmarchy`.
   This template uses `agent` / UID 1000 / `/home/agent` as required by
   Docker Sandboxes. The fast `Dockerfile` starts FROM `devmarchy:4.5.0` and
   renames the account with `usermod`/`groupmod`. Upstream `ARG USERNAME`
   was not enough on its own because `OMARCHY_PATH` was hardcoded.

3. **PATH / `omarchy` CLI.** Upstream set `PATH="$OMARCHY_PATH/bin:..."` in
   the same `ENV` instruction that defined `OMARCHY_PATH`. Docker expands
   that to `/bin:...`, so `omarchy` was not on PATH. PATH is now a separate
   `ENV` with an explicit prefix of `/home/agent/.local/share/omarchy/bin`.

4. **bashrc / env-bootstrap.** Omarchy 4.5.0's bashrc sources
   `/usr/share/omarchy/default/bash/env-bootstrap`, which does not exist in
   a git-clone install, and `env-bootstrap` resets `OMARCHY_PATH` to
   `/usr/share/omarchy` unless `/etc/omarchy.conf` is present. This image
   writes `/etc/omarchy.conf`, symlinks `/usr/share/omarchy` to the clone,
   and uses a bashrc that sources env-bootstrap from `$OMARCHY_PATH`.

5. **Sandbox shell contract.** `/etc/sandbox-persistent.sh` (owned by agent),
   sourced from `/etc/profile.d/` and `~/.bashrc`; `BASH_ENV` and `HOME` set;
   CA bundle env vars pointed at `/etc/ssl/certs/ca-certificates.crt`;
   workspace and XDG-style dirs created; `WORKDIR /home/agent/workspace`;
   `CMD ["/bin/bash"]` with no agent ENTRYPOINT.

The local image `omarchy-sandbox:4.5.0` was built from `Dockerfile` (the
FROM-devmarchy adapter) so pacman/yay/npm/nvim layers did not have to be
rebuilt. Use `omarchy-sandbox.dockerfile` to rebuild from
`archlinux:base-devel` on another machine.

## Image size and leftover empty home

The local image built FROM `devmarchy:4.5.0` is about 6.42 GB, roughly 1.1 GB
larger than the 5.3 GB base. Moving `/home/devmarchy` to `/home/agent` copies
the home tree into a new overlay layer.

An empty `/home/devmarchy` directory may still appear in that image because of
an overlay whiteout quirk on this builder. It is not the live home: `/etc/passwd`
points at `/home/agent`, there are no `devmarchy` references in passwd, group,
or sudoers, and the directory is empty. The standalone Dockerfile creates
`/home/agent` from the start and does not have this leftover; rebuilding with
it also avoids the extra 1.1 GB copy-up.
