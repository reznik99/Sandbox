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
        # Editor: LazyVim reads its config from /home/sandbox/.config/nvim
        # (bind-mounted from host). Plugins live in named volumes so they
        # survive sandbox-nuke. See `Persistent state` in README.
        neovim fd-find \
        # Utilities
        openssh-clients git fzf lsd gnupg2 \
        openssl curl wget vim findutils procps-ng ripgrep \
        # Caruso work: GitHub CLI, JSON wrangling, protoc compiler
        # (codegen plugins are installed via `go install` below).
        gh jq protobuf-compiler \
        # Codex CLI sandboxing backend
        bubblewrap \
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
# Enforce a 3-day cooldown on every npm install inside the sandbox — neutralises
# fast-burn supply-chain worms (Shai-Hulud, etc.) that get yanked within hours.
# Override per-command with `npm install --min-release-age=0 <pkg>` when needed.
ENV NPM_CONFIG_MIN_RELEASE_AGE=3

# Fedora 44 ships npm 11.8.0, but `min-release-age` only exists in npm ≥ 11.10.0.
# Self-upgrade npm into NPM_CONFIG_PREFIX so the cooldown actually takes effect.
# The bootstrap install runs as the old npm 11.8.0 (which ignores the env var),
# so the upgrade itself can't be blocked by the cooldown.
RUN npm install -g npm@latest

# Fedora pins GOTOOLCHAIN=local, but tools like gopls may require a newer Go
# than the distro package (e.g. gopls v0.22 needs go >= 1.26 vs Fedora's 1.25).
# `auto` lets `go install` fetch the required toolchain on demand — still
# checksum-verified via GOSUMDB, so the supply-chain posture is unchanged.
ENV GOTOOLCHAIN=auto

# Codex CLI and OpenCode — installed alongside Claude. Codex state lives in
# ~/.codex (sandbox-codex volume). OpenCode stores provider credentials under
# ~/.local/share/opencode/auth.json and global config under ~/.config/opencode.
# Those volumes are mounted only in sandbox-code (same trust model as Claude).
RUN npm install -g @openai/codex

RUN npm install -g opencode-ai

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

# === Caruso work tooling ===
# Everything below is for the work environment (gh + AWS dev + protobuf codegen
# + Postman). Keep these in their own blocks so they're easy to revert and the
# layers cache independently of the personal-project tools above.

# Caruso Go toolchain: buf for proto workspace mgmt, protoc-gen-* for codegen,
# mockery for test mocks, golines/gci for formatting. protoc-gen-validate is
# pinned to v0.10.1 per Caruso convention — newer versions emit incompatible
# generated code. The rest float with the rebuild (same caveat as above re:
# `go install @latest` having no release-age cooldown).
RUN go install github.com/bufbuild/buf/cmd/buf@latest && \
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest && \
    go install github.com/envoyproxy/protoc-gen-validate@v0.10.1 && \
    go install github.com/vektra/mockery/v2@latest && \
    go install github.com/segmentio/golines@latest && \
    go install github.com/daixiang0/gci@latest

# Postman CLI — used by /postman-run-tests and /postman-run-integration-tests.
# Same 3-day cooldown as the npm block above.
RUN npm install -g postman-cli

CMD ["/bin/bash"]
