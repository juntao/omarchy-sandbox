# Fast local adapter: reuse the already-built devmarchy:4.5.0 image.
# To rebuild from scratch on another machine, use omarchy-sandbox.dockerfile.
FROM devmarchy:4.5.0

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
            '. /etc/sandbox-persistent.sh'; \
    } > "$tmp" \
    && install -o agent -g agent -m 0644 "$tmp" /home/agent/.bashrc \
    && rm -f "$tmp" \
    && touch /etc/sandbox-persistent.sh \
    && chown agent:agent /etc/sandbox-persistent.sh \
    && chmod 0644 /etc/sandbox-persistent.sh \
    && printf '%s\n' '. /etc/sandbox-persistent.sh' > /etc/profile.d/sandbox-persistent.sh \
    && chmod 0644 /etc/profile.d/sandbox-persistent.sh

# Set PATH in a separate ENV from OMARCHY_PATH. Docker does not expand a
# variable that is defined in the same ENV instruction, which previously
# turned $OMARCHY_PATH/bin into /bin and hid the omarchy CLI.
ENV HOME=/home/agent
ENV OMARCHY_PATH=/home/agent/.local/share/omarchy
ENV PATH="/home/agent/.local/share/omarchy/bin:/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV BASH_ENV=/etc/sandbox-persistent.sh
ENV EDITOR=nvim
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# usermod -m can leave an empty /home/devmarchy that lower overlay
# layers still expose; white it out in a later layer.
USER root
RUN rm -rf /home/devmarchy && test ! -e /home/devmarchy

USER agent
WORKDIR /home/agent/workspace
CMD ["/bin/bash"]
