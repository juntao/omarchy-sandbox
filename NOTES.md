# Changes versus upstream devmarchy

Upstream: https://github.com/ThatBlokeJosh/devmarchy (defaults to Omarchy v3.8.1).

Built here against Omarchy v4.5.0 (commit ac2690cd7be4f47e4a255f5e2e78d904d436b068).

Fixes applied:

1. **fastfetch config path (v4.x).** Omarchy 4.x moved the config from
   `config/fastfetch` to `etc/fastfetch`. The standalone Dockerfile copies
   whichever location exists.

2. **User account.** Upstream uses `devmarchy` with home `/home/devmarchy`.
   This template uses `agent` / UID 1000 / `/home/agent` as required by
   Docker Sandboxes. The `Dockerfile` creates that account directly.
   Upstream `ARG USERNAME` was not enough on its own because `OMARCHY_PATH`
   was hardcoded.

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

The image is built from `Dockerfile`, starting at `archlinux:base-devel`.
An earlier fast adapter built `FROM devmarchy:4.5.0` and renamed the
account; it carried devmarchy's caches and a second copy of the home
directory (6.45 GB), so it was removed.

6. **Herdr and the official Omarchy package repo.** The upstream image did
   not install `herdr`. Both Dockerfiles download `omarchy-keyring` and
   `herdr` from `https://pkgs.omarchy.org/stable/$arch`, verify each file
   against the SHA-256 in the official repo database, and install them
   with `pacman -U`. That avoids `pacman-key --init`, which can stall in
   a Docker build when the container has little entropy. The official
   `pkgs@omarchy.org` key (`40DFB630FF42BCFFB047046CF0134EE680CAC571`) is
   imported afterward with a timeout; if that succeeds, `[omarchy]` is
   added with required signatures, otherwise with optional signatures so
   later syncs still work. Omarchy's `config/herdr/config.toml` is copied
   to `~/.config/herdr`. The older `omarchy-herdr` package conflicts with
   `herdr` and is not installed. The desktop app `herdr-app` (Wayland /
   Vulkan) is also not installed.

7. **Headless Herdr server.** `/usr/local/bin/omarchy-sandbox-ensure-herdr`
   starts `herdr server` if it is not already running. `/etc/sandbox-env.sh`
   calls that helper, then sources `/etc/sandbox-persistent.sh`. `BASH_ENV`
   and login shells use `sandbox-env.sh`. Set `OMARCHY_SANDBOX_SKIP_HERDR=1`
   to skip the auto-start.


8. **BASH_ENV re-entry guard.** With `BASH_ENV=/etc/sandbox-env.sh` set,
   every bash process, including the ensure-herdr helper itself, sources
   that file. Without a guard, the helper re-enters through `BASH_ENV` and
   fork-loops. `sandbox-env.sh` returns immediately when
   `OMARCHY_SANDBOX_ENV_SOURCED` is set, and the helper sets
   `OMARCHY_SANDBOX_ENSURE_HERDR_RUNNING`. `ENV BASH_ENV` is the last
   setting in the `Dockerfile`, so no build step (makepkg, yay, and nvim are
   bash scripts) inherits it or starts a Herdr server during the build.

9. **Cleanup policy: nothing temporary is ever committed to a layer.**
   Deleting files in a later step does not shrink an image; the earlier
   layer still carries them. So every `RUN` that downloads or builds
   something cleans up in the same `RUN`:

   | Step | Cleaned in the same RUN |
   | --- | --- |
   | `pacman -Syu` / `-S` | `pacman -Scc`, `/var/cache/pacman/pkg/*`, `/tmp/*` |
   | Herdr install script | `pacman -Scc`, its temp dir, `/tmp/*` |
   | `npm install -g` | `npm cache clean --force`, `/root/.npm`, `/root/.cache`, `/tmp/*` |
   | yay-bin (`makepkg -si`) | build dir, `~/.cache`, `pacman -Scc` |
   | `yay -S claude-code` | `--cleanafter`, `~/.cache` (yay build dir), `pacman -Scc` |
   | LazyVim sync | `~/.cache` (tree-sitter sources, bytecode cache), `/tmp/*` |

   Not installed or not kept at all:

   - **Theme media.** Omarchy's `themes/*/backgrounds` (wallpapers and
     intro videos) and theme preview images, about 160 MB, are only used by
     the Hyprland desktop. The text theme files stay.
   - **Omarchy `.git`.** Even a depth-1 clone stores another copy of every
     file (~174 MB). The tag and commit are written to
     `/etc/omarchy-sandbox-release`; `omarchy-version` prints `dev`.
   - **LazyVim starter `.git`.** The starter is meant to become your own
     config. Plugin checkouts under `~/.local/share/nvim/lazy` keep their
     git data so `:Lazy update` works.
   - **`-debug` packages.** makepkg's `debug` option is turned off in
     `/etc/makepkg.conf` (yay-bin used to bring in `yay-bin-debug`).
   - **opencode's unused binary.** npm installs both `opencode-linux-x64`
     and `-baseline` (~205 MB each). After opencode's postinstall runs
     (npm skipped it, which left `opencode` broken), the one it did not
     link is deleted.
   - **man-db.** The Arch base image's `NoExtract` never installs man
     pages, so `man` had nothing to show. `tldr` and `--help` remain.

   Kept on purpose: base-devel (gcc, make, and gdb via debugedit) so agents
   can compile code and build AUR packages; `mise` (157 MB) because
   Omarchy's shell setup and dev-env scripts use it for language runtimes;
   the pacman sync databases; LazyVim plugins and the Mason registry.

   Result: 3.2 GB unpacked, about 1.27 GB compressed on Docker Hub (was
   6.45 GB / 3.3 GB before any cleanup), well under Docker cloud
   sandboxes' 3 GiB pull limit without flattening the image.
