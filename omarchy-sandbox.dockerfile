# Standalone Docker Sandboxes template: Arch + Omarchy CLI/TUI stack.
# Default Omarchy version is v4.5.0. Override with:
#   docker build -f omarchy-sandbox.dockerfile --build-arg OMARCHY_VERSION=v4.5.0 -t omarchy-sandbox:4.5.0 .
#
# This file does not need the intermediate devmarchy:4.5.0 image.
FROM archlinux:base-devel AS build

ARG OMARCHY_VERSION=v4.5.0
# Keep this agent for Docker Sandboxes (UID 1000, home /home/agent).
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=$USER_UID

USER root

RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm --needed \
        ca-certificates curl git sudo \
        bash-completion bat dust eza expac fastfetch fd fzf \
        gum inetutils inxi jq lazygit less man-db plocate ripgrep \
        socat starship tldr tmux tree-sitter-cli unzip usage whois \
        xmlstarlet zoxide \
        luarocks mise nodejs npm nvim openssh \
        python-poetry-core python-pynvim ruby \
    && pacman -Scc --noconfirm

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
RUN git clone --branch $OMARCHY_VERSION --depth 1 \
        https://github.com/omacom/omarchy.git /home/agent/.local/share/omarchy

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
RUN npm install -g opencode-ai @openai/codex @google/gemini-cli @github/copilot

# Tell Omarchy this is a linked/dev tree so env-bootstrap keeps OMARCHY_PATH
# and prepends its bin directory (it would otherwise assume /usr/bin/omarchy-*).
RUN printf '%s\n' 'OMARCHY_PATH=/home/agent/.local/share/omarchy' > /etc/omarchy.conf \
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
ENV BASH_ENV=/etc/sandbox-env.sh
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
    && BASH_ENV= /tmp/install-omarchy-repo-and-herdr.sh \
    && rm -f /tmp/install-omarchy-repo-and-herdr.sh

USER $USERNAME

RUN git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin \
    && cd /tmp/yay-bin && makepkg -si --noconfirm \
    && rm -rf /tmp/yay-bin

RUN yay -S --noconfirm --answerdiff None --answerclean None claude-code

RUN git clone https://github.com/LazyVim/starter /home/agent/.config/nvim \
    && nvim --headless "+Lazy! sync" +qa 2>/dev/null || true

# docker run/exec do not set SHELL. Without it, the auto-started Herdr
# server opens new panes in /bin/sh instead of bash.
ENV SHELL=/bin/bash
WORKDIR /home/agent/workspace
# Shell template: do not set ENTRYPOINT to an agent. Launch Codex with
#   sbx run codex --template juntaoyuan/omarchy-sandbox:4.5.0
# or run `codex` inside a shell sandbox.
CMD ["/bin/bash"]

# Finish opencode, drop package caches, then flatten everything into one layer. Files that
# earlier layers wrote and later layers deleted or moved (the renamed home,
# npm/yay/pacman caches) otherwise stay in the image. Flattening keeps the
# compressed image under Docker cloud sandboxes' 3 GiB pull limit.
USER root
# npm skipped opencode-ai's postinstall in this build; without it `opencode`
# exits with "postinstall script was not run".
RUN export BASH_ENV= OMARCHY_SANDBOX_SKIP_HERDR=1 \
    && cd /usr/lib/node_modules/opencode-ai && node postinstall.mjs
# Also remove any Herdr runtime files a root build step left in the agent's
# home, and make sure everything under it belongs to agent.
RUN export BASH_ENV= OMARCHY_SANDBOX_SKIP_HERDR=1 \
    && rm -rf /root/.npm /root/.cache /home/agent/.npm /home/agent/.cache/yay \
        /var/cache/pacman/pkg/* /tmp/* /var/tmp/* \
        /home/agent/.config/herdr/.plugins.lock /home/agent/.config/herdr/*.sock \
        /home/agent/.config/herdr/herdr-server.log /home/agent/.config/herdr/session.json \
        /home/agent/.local/state/herdr /home/agent/.local/state/herdr-server.* \
    && chown -R agent:agent /home/agent

FROM scratch
COPY --from=build / /
ENV PATH="/home/agent/.local/share/omarchy/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    LANG=C.UTF-8 \
    HOME=/home/agent \
    OMARCHY_PATH=/home/agent/.local/share/omarchy \
    BASH_ENV=/etc/sandbox-env.sh \
    EDITOR=nvim \
    SHELL=/bin/bash \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
USER agent
WORKDIR /home/agent/workspace
CMD ["/bin/bash"]
