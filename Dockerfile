# Fast local adapter: reuse the already-built devmarchy:4.5.0 image.
# To rebuild from scratch on another machine, use omarchy-sandbox.dockerfile.
FROM devmarchy:4.5.0 AS build

USER root

# Rename the existing UID 1000 account to the Docker Sandboxes contract
# (agent / /home/agent) and move the home directory in place.
RUN groupmod -n agent devmarchy \
    && usermod -l agent -d /home/agent -m devmarchy \
    && rm -f /etc/sudoers.d/devmarchy \
    && echo 'agent ALL=(root) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && mkdir -p \
        /home/agent/workspace \
        /home/agent/.local/bin \
        /home/agent/.local/share \
        /home/agent/.local/state \
        /home/agent/.docker/sandbox/locks \
    && chown agent:agent \
        /home/agent \
        /home/agent/workspace \
        /home/agent/.local \
        /home/agent/.local/bin \
        /home/agent/.local/share \
        /home/agent/.local/state \
        /home/agent/.docker \
        /home/agent/.docker/sandbox \
        /home/agent/.docker/sandbox/locks \
    && rm -rf /home/devmarchy \
    && test ! -e /home/devmarchy \
    && ! grep -q /home/devmarchy /etc/passwd /etc/group /etc/shadow \
    && printf '%s\n' 'OMARCHY_PATH=/home/agent/.local/share/omarchy' > /etc/omarchy.conf \
    && ln -sfn /home/agent/.local/share/omarchy /usr/share/omarchy

# Point Omarchy's bashrc at the tree under the agent's home, then arrange
# for login, interactive, and non-interactive bash to read the persistent
# env file. Do not put completion scripts in that file.
RUN tmp=/tmp/bashrc.agent \
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

# Set PATH in a separate ENV from OMARCHY_PATH. Docker does not expand a
# variable that is defined in the same ENV instruction, which previously
# turned $OMARCHY_PATH/bin into /bin and hid the omarchy CLI.
ENV HOME=/home/agent
ENV OMARCHY_PATH=/home/agent/.local/share/omarchy
ENV PATH="/home/agent/.local/share/omarchy/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV BASH_ENV=/etc/sandbox-env.sh
ENV EDITOR=nvim
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# usermod -m can leave an empty /home/devmarchy that lower overlay
# layers still expose; white it out in a later layer.
USER root
RUN rm -rf /home/devmarchy && test ! -e /home/devmarchy

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

# docker run/exec do not set SHELL. Without it, the auto-started Herdr
# server opens new panes in /bin/sh instead of bash.
ENV SHELL=/bin/bash
USER agent
WORKDIR /home/agent/workspace
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
