FROM fedora:latest

# Use a Build Argument for the UID to match your host user
ARG USER_ID=1000
ARG GROUP_ID=1000

RUN dnf upgrade -y --refresh && \
    dnf install -y \
        # Core Dev Tools
        nodejs24 nodejs24-npm golang \
        # Build Tools (Optional but recommended for CGO/Native modules)
        gcc gcc-c++ make \
        # Utilities
        openssh-clients git fzf lsd gnupg2 \
        openssl curl wget vim findutils procps-ng ripgrep \
        && \
    dnf clean all && \
    rm -rf /var/cache/dnf && \
    ln -s /usr/bin/node-24 /usr/local/bin/node && \
    ln -s /usr/bin/npm-24 /usr/local/bin/npm && \
    ln -s /usr/bin/npx-24 /usr/local/bin/npx

# Create group and user matching the host IDs
RUN groupadd -g $GROUP_ID sandbox && \
    useradd -u $USER_ID -g $GROUP_ID -m -s /bin/bash sandbox

# Ensure the sandbox user owns their home
COPY --chown=sandbox:sandbox bashrc /home/sandbox/.bashrc

USER sandbox
WORKDIR /home/sandbox

# Pre-create persistent state dirs so the named volume mount inherits
# correct ownership (sandbox:sandbox) on first run.
# Also redirect ~/.claude.json (which Claude writes at $HOME, outside
# ~/.claude/) into the same volume via a symlink. Claude uses
# open()/write()/close() (it keeps its own backups, doesn't atomic-rename),
# so the symlink survives writes.
RUN mkdir -p /home/sandbox/.claude && \
    ln -s /home/sandbox/.claude/claude.json /home/sandbox/.claude.json

# Install Claude Code as the sandbox user
RUN curl -fsSL https://claude.ai/install.sh | bash

# Set Go paths inside the container
ENV GOPATH=/home/sandbox/go
ENV PATH=$PATH:$GOPATH/bin
# Ensure the Claude binary is in the PATH
ENV PATH="/home/sandbox/.local/bin:${PATH}"
# Redirect npm's global prefix to a user-writable path so `npm install -g`
# works without root. Binaries land in /home/sandbox/.local/bin (already in PATH).
ENV NPM_CONFIG_PREFIX=/home/sandbox/.local
# Enforce a 2-day cooldown on every npm install inside the sandbox — neutralises
# fast-burn supply-chain worms (Shai-Hulud, etc.) that get yanked within hours.
# Override per-command with `npm install --min-release-age=0 <pkg>` when needed.
ENV NPM_CONFIG_MIN_RELEASE_AGE=2

# Fedora 44 ships npm 11.8.0, but `min-release-age` only exists in npm ≥ 11.10.0.
# Self-upgrade npm into NPM_CONFIG_PREFIX so the cooldown actually takes effect.
# The bootstrap install runs as the old npm 11.8.0 (which ignores the env var),
# so the upgrade itself can't be blocked by the cooldown.
RUN npm install -g npm@latest

CMD ["/bin/bash"]
