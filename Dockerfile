FROM fedora:latest

# Use a Build Argument for the UID to match your host user
ARG USER_ID=1000
ARG GROUP_ID=1000

# Go and Node come from upstream tarballs below, not dnf: Fedora's `golang` is
# built with GOEXPERIMENT=nodwarf5, which breaks GOTOOLCHAIN=auto switching.
RUN dnf upgrade -y --refresh && \
    dnf install -y \
        # Build Tools
        gcc gcc-c++ make \
        # LazyVim config bind-mounted from host; plugins in named volumes.
        neovim fd-find \
        # Utilities
        openssh-clients git fzf lsd gnupg2 \
        openssl curl wget vim findutils procps-ng ripgrep \
        # Codex CLI sandboxing backend
        bubblewrap \
        && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Go — stock upstream toolchain (no LTS; latest stable patch). SHA-256 per go.dev/dl.
ARG GO_VERSION=1.26.4
ARG GO_SHA256=1153d3d50e0ac764b447adfe05c2bcf08e889d42a02e0fe0259bd47f6733ad7f
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz && \
    echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - && \
    tar -C /usr/local -xzf /tmp/go.tgz && \
    rm /tmp/go.tgz

# Node — v24 (Krypton) Active LTS. SHA-256 per nodejs.org/dist.
ARG NODE_VERSION=24.17.0
ARG NODE_SHA256=e0472427aa791ad80bdc426ff7cc73cdd28ed0f616d1ff9689a23a7f47f1265f
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" -o /tmp/node.tgz && \
    echo "${NODE_SHA256}  /tmp/node.tgz" | sha256sum -c - && \
    mkdir -p /usr/local/node && \
    tar -C /usr/local/node --strip-components=1 -xzf /tmp/node.tgz && \
    rm /tmp/node.tgz

ENV PATH="/usr/local/go/bin:/usr/local/node/bin:${PATH}"

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
# ~/.agents is symlinked into the Codex volume too — it stores shared agent
# skill content (read by Codex at ~/.agents/skills/) and we want it to live
# in the same persistent volume as Codex's own state.
#   .claude              — Claude Code auth/settings/memory  (sandbox-claude)
#   .codex                   — Codex CLI auth/config/sessions      (sandbox-codex)
#   .codex/agents            — shared agent skills, exposed as ~/.agents via symlink
#   .local/share/opencode    — OpenCode auth/data                  (sandbox-opencode-data)
#   .config/opencode         — OpenCode global config              (sandbox-opencode-config)
#   .local/share/nvim        — LazyVim plugins + compiled treesitter parsers  (sandbox-nvim-share)
#   .local/state/nvim        — undo history, shada, sessions, LSP logs        (sandbox-nvim-state)
RUN mkdir -p /home/sandbox/.claude \
             /home/sandbox/.codex/agents \
             /home/sandbox/.local/share/opencode \
             /home/sandbox/.config/opencode \
             /home/sandbox/.local/share/nvim \
             /home/sandbox/.local/state/nvim && \
    ln -s /home/sandbox/.claude/claude.json /home/sandbox/.claude.json && \
    ln -s /home/sandbox/.codex/agents       /home/sandbox/.agents

# Set Go paths inside the container
ENV GOPATH=/home/sandbox/go
ENV PATH=$PATH:$GOPATH/bin
# Ensure the Claude binary is in the PATH
ENV PATH="/home/sandbox/.local/bin:${PATH}"
# Redirect npm's global prefix to a user-writable path so `npm install -g`
# works without root. Binaries land in /home/sandbox/.local/bin (already in PATH).
ENV NPM_CONFIG_PREFIX=/home/sandbox/.local
# Enforce a 3-day cooldown on every npm install inside the sandbox — neutralises
# fast-burn supply-chain worms (Shai-Hulud, etc.) that get yanked within hours.
# Override per-command with `npm install --min-release-age=0 <pkg>` when needed.
ENV NPM_CONFIG_MIN_RELEASE_AGE=3

# Keep npm current; the version bundled with Node lags upstream releases.
RUN npm install -g npm@latest

# Let `go install` / go.mod fetch newer toolchains on demand, checksum-verified via GOSUMDB.
ENV GOTOOLCHAIN=auto

# Claude Code, Codex CLI, and OpenCode. State lives in separate volumes mounted
# only in sandbox-code. OpenCode stores provider credentials under
# ~/.local/share/opencode/auth.json and global config under ~/.config/opencode.
RUN npm install -g @anthropic-ai/claude-code @openai/codex opencode-ai

# Go-based LSPs, formatters, linter, debugger.
# `go install` has no min-release-age equivalent, but GOSUMDB (sum.golang.org)
# provides checksum verification by default. Versions are pinned to whatever
# was @latest at image build time — rebuild the image to update.
RUN go install golang.org/x/tools/gopls@latest && \
    go install mvdan.cc/gofumpt@latest && \
    go install golang.org/x/tools/cmd/goimports@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest

# npm-based LSPs, formatters, linter. NPM_CONFIG_MIN_RELEASE_AGE=3 (set above)
# enforces a 3-day publish-age cooldown — npm resolves to the latest version
# that is at least 3 days old. Same cooldown applies on rebuild.
RUN npm install -g \
        typescript \
        @vtsls/language-server \
        prettier \
        eslint_d \
        vscode-langservers-extracted

CMD ["/bin/bash"]
