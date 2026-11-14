# Docker Sandboxes template: Arch + Omarchy CLI/TUI stack, no desktop.
# Default Omarchy version is v4.5.0. Build with:
#   docker build --build-arg OMARCHY_VERSION=v4.5.0 -t omarchy-sandbox:4.5.0 .
#
# Cleanup policy: every RUN that downloads or builds something deletes its
# own caches (pacman, npm, yay/makepkg, nvim, /tmp) before the step ends,
# so nothing temporary is ever committed to an image layer. See NOTES.md.
FROM archlinux:base-devel

ARG OMARCHY_VERSION=v4.5.0
# Keep this agent for Docker Sandboxes (UID 1000, home /home/agent).
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=$USER_UID

USER root

# man-db is left out: the Arch base image never extracts man pages
# (NoExtract in /etc/pacman.conf), so `man` would have nothing to show.
# Use `tldr` or `<cmd> --help`. makepkg's debug option is turned off so
# AUR builds (yay, claude-code, anything an agent builds) do not also
# install -debug packages.
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm --needed \
        ca-certificates curl git sudo \
        bash-completion bat dust eza expac fastfetch fd fzf \
        gum inetutils inxi jq lazygit less plocate ripgrep \
        socat starship tldr tmux tree-sitter-cli unzip usage whois \
        xmlstarlet zoxide \
        luarocks mise nodejs npm nvim openssh \
        python-poetry-core python-pynvim ruby \
    && sed -i 's/^\(OPTIONS=(.*\) debug/\1 !debug/' /etc/makepkg.conf \
    && grep -q '^OPTIONS=(.* !debug' /etc/makepkg.conf \
    && pacman -Scc --noconfirm \
    && rm -rf /var/cache/pacman/pkg/* /tmp/* /root/.cache

# Non-root agent account required by Docker Sandboxes.
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -d /home/agent -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && mkdir -p \
        /home/agent/workspace \
        /home/agent/.local/bin \
        /home/agent/.local/share \
        /home/agent/.local/state \
        /home/agent/.docker/sandbox/locks \
    && chown -R $USERNAME:$USERNAME /home/agent

USER $USERNAME
WORKDIR /home/agent

# Official repo is omacom/omarchy; the v4.5.0 tag is also on basecamp/omarchy.
# Theme wallpapers, intro videos, and preview images are only used by the
# Hyprland desktop (theme switcher, lock screen, boot splash), so they are
# not kept; the text theme files (colors.toml, neovim.lua, ...) stay. The
# clone's .git would hold another full copy of those media files (~174 MB
# even at depth 1), so it is dropped too. The tag and commit are recorded
# in /etc/omarchy-sandbox-release (omarchy-version then prints "dev").
RUN git clone --branch $OMARCHY_VERSION --depth 1 \
        https://github.com/omacom/omarchy.git /home/agent/.local/share/omarchy \
    && cd /home/agent/.local/share/omarchy \
    && printf 'OMARCHY_VERSION=%s\nOMARCHY_COMMIT=%s\n' "$OMARCHY_VERSION" "$(git rev-parse HEAD)" \
        > .sandbox-release \
    && rm -rf .git themes/*/backgrounds \
    && find themes -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' \) \
        -delete

# v4.x moved fastfetch from config/fastfetch to etc/fastfetch; keep a fallback
# so older OMARCHY_VERSION tags still copy their config.
RUN mkdir -p /home/agent/.config \
    && cp -r /home/agent/.local/share/omarchy/config/git /home/agent/.config/ \
    && cp -r /home/agent/.local/share/omarchy/config/tmux /home/agent/.config/ \
    && cp -r /home/agent/.local/share/omarchy/config/omarchy /home/agent/.config/ \
    && cp -r /home/agent/.local/share/omarchy/config/lazygit /home/agent/.config/ \
    && if [ -d /home/agent/.local/share/omarchy/config/fastfetch ]; then \
         cp -r /home/agent/.local/share/omarchy/config/fastfetch /home/agent/.config/; \
       elif [ -d /home/agent/.local/share/omarchy/etc/fastfetch ]; then \
         cp -r /home/agent/.local/share/omarchy/etc/fastfetch /home/agent/.config/; \
       fi \
    && cp /home/agent/.local/share/omarchy/config/starship.toml /home/agent/.config/ \
    && if [ -d /home/agent/.local/share/omarchy/config/herdr ]; then \
         cp -r /home/agent/.local/share/omarchy/config/herdr /home/agent/.config/; \
       fi \
    && mkdir -p /home/agent/.config/omarchy/branding \
    && cp /home/agent/.local/share/omarchy/icon.txt /home/agent/.config/omarchy/branding/about.txt

USER root

# Global CLIs (codex, opencode, gemini, copilot) land in /usr/bin.
# npm skips opencode-ai's postinstall here, and `opencode` then exits with
# "postinstall script was not run", so run it. It links the binary from one
# of two optional packages (opencode-linux-x64 or -baseline, ~205 MB each);
# the one it did not pick is deleted. npm's cache goes in the same step.
RUN npm install -g opencode-ai @openai/codex @google/gemini-cli @github/copilot \
    && cd /usr/lib/node_modules/opencode-ai \
    && node postinstall.mjs \
    && for d in node_modules/opencode-linux-*; do \
         [ "$(stat -c %i "$d/bin/opencode")" = "$(stat -c %i bin/opencode.exe)" ] || rm -rf "$d"; \
       done \
    && test -x bin/opencode.exe \
    && npm cache clean --force \
    && rm -rf /root/.npm /root/.cache /tmp/*

# Tell Omarchy this is a linked/dev tree so env-bootstrap keeps OMARCHY_PATH
# and prepends its bin directory (it would otherwise assume /usr/bin/omarchy-*).
RUN printf '%s\n' 'OMARCHY_PATH=/home/agent/.local/share/omarchy' > /etc/omarchy.conf \
    && install -m 0644 /home/agent/.local/share/omarchy/.sandbox-release /etc/omarchy-sandbox-release \
    && rm -f /home/agent/.local/share/omarchy/.sandbox-release \
    && ln -sfn /home/agent/.local/share/omarchy /usr/share/omarchy \
    && tmp=/tmp/bashrc.agent \
    && { \
        printf '%s\n' \
            '# Omarchy environment (OMARCHY_PATH + PATH)' \
            'if [[ -r ${OMARCHY_PATH:-/home/agent/.local/share/omarchy}/default/bash/env-bootstrap ]]; then' \
            '  source "${OMARCHY_PATH:-/home/agent/.local/share/omarchy}/default/bash/env-bootstrap"' \
            'elif [[ -r /usr/share/omarchy/default/bash/env-bootstrap ]]; then' \
            '  source /usr/share/omarchy/default/bash/env-bootstrap' \
            'fi' \
            '' \
            '# If not running interactively, do not load aliases or completion.' \
            '[[ $- != *i* ]] && return' \
            '' \
            'if [[ -r ${OMARCHY_PATH:-/home/agent/.local/share/omarchy}/default/bash/rc ]]; then' \
            '  source "${OMARCHY_PATH:-/home/agent/.local/share/omarchy}/default/bash/rc"' \
            'fi' \
            '' \
            '# Add your own exports, aliases, and functions here.' \
            '' \
            '. /etc/sandbox-env.sh'; \
    } > "$tmp" \
    && install -o agent -g agent -m 0644 "$tmp" /home/agent/.bashrc \
    && rm -f "$tmp" \
    && touch /etc/sandbox-persistent.sh \
    && chown agent:agent /etc/sandbox-persistent.sh \
    && chmod 0644 /etc/sandbox-persistent.sh \
    && printf '%s\n' '. /etc/sandbox-env.sh' > /etc/profile.d/sandbox-env.sh \
    && chmod 0644 /etc/profile.d/sandbox-env.sh

# PATH is set in its own ENV instruction so $OMARCHY_PATH is not expanded
# from an empty value (a pre-existing devmarchy bug).
ENV HOME=/home/agent
ENV OMARCHY_PATH=/home/agent/.local/share/omarchy
ENV PATH="/home/agent/.local/share/omarchy/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV EDITOR=nvim
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Official Omarchy repo (herdr) plus a headless Herdr server that starts
# with the shell. This is the agent-OS path: multiplexers and CLIs, no desktop.
COPY scripts/omarchy-sandbox-ensure-herdr /usr/local/bin/omarchy-sandbox-ensure-herdr
COPY scripts/sandbox-env.sh /etc/sandbox-env.sh
COPY scripts/install-omarchy-repo-and-herdr.sh /tmp/install-omarchy-repo-and-herdr.sh
RUN chmod 0755 /usr/local/bin/omarchy-sandbox-ensure-herdr \
        /tmp/install-omarchy-repo-and-herdr.sh \
    && chmod 0644 /etc/sandbox-env.sh \
    && /tmp/install-omarchy-repo-and-herdr.sh \
    && rm -rf /tmp/* /var/cache/pacman/pkg/*

USER $USERNAME

RUN git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin \
    && cd /tmp/yay-bin && makepkg -si --noconfirm \
    && cd / && rm -rf /tmp/yay-bin /home/agent/.cache \
    && sudo pacman -Scc --noconfirm

RUN yay -S --noconfirm --answerdiff None --answerclean None --cleanafter claude-code \
    && rm -rf /home/agent/.cache \
    && sudo pacman -Scc --noconfirm \
    && sudo rm -rf /var/cache/pacman/pkg/*

# LazyVim starter: its .git is dropped (the starter is meant to be your
# own config). Plugins under ~/.local/share/nvim/lazy keep their git
# checkouts so :Lazy update works. ~/.cache/nvim (tree-sitter parser
# sources, bytecode cache) is rebuilt on demand.
RUN git clone https://github.com/LazyVim/starter /home/agent/.config/nvim \
    && rm -rf /home/agent/.config/nvim/.git \
    && { nvim --headless "+Lazy! sync" +qa 2>/dev/null || true; } \
    && rm -rf /home/agent/.cache /tmp/*

# Google Chrome plus agent CLI tools. Installed here, after yay and
# before BASH_ENV, so the build does not start Herdr. The PATH wrapper
# adds --no-sandbox and --disable-dev-shm-usage (the setuid sandbox
# does not work as a non-root user in this container). Do not run
# `agent-browser install`: that would download a second Chrome.
COPY --chown=agent:agent scripts/google-chrome-sandbox-wrapper /tmp/google-chrome-sandbox-wrapper
COPY --chown=agent:agent scripts/install-chrome-and-devtools.sh /tmp/install-chrome-and-devtools.sh
RUN chmod 0755 /tmp/google-chrome-sandbox-wrapper \
        /tmp/install-chrome-and-devtools.sh \
    && /tmp/install-chrome-and-devtools.sh

# Agent instructions (browser CLIs, Herdr, tools). Also copied to
# workspace; a host bind-mount of that directory hides those copies.
COPY --chown=agent:agent context.md /home/agent/AGENTS.md
RUN cp -a /home/agent/AGENTS.md /home/agent/CLAUDE.md \
    && cp -a /home/agent/AGENTS.md /home/agent/workspace/AGENTS.md \
    && cp -a /home/agent/AGENTS.md /home/agent/workspace/CLAUDE.md

# docker run/exec do not set SHELL. Without it, the auto-started Herdr
# server opens new panes in /bin/sh instead of bash.
ENV SHELL=/bin/bash
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/local/bin/google-chrome-stable
ENV CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1 \
    CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1
# Set last so no build step above sources it (makepkg, yay, and nvim are
# bash scripts and would otherwise start the Herdr server mid-build).
ENV BASH_ENV=/etc/sandbox-env.sh
WORKDIR /home/agent/workspace
# Shell template: do not set ENTRYPOINT to an agent. Launch Codex with
#   sbx run codex --template juntaoyuan/omarchy-sandbox:4.5.0
# or run `codex` inside a shell sandbox.
CMD ["/bin/bash"]
