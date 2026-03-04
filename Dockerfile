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
    rm -rf /var/cache/dnf

# Create group and user matching the host IDs
RUN groupadd -g $GROUP_ID sandbox && \
    useradd -u $USER_ID -g $GROUP_ID -m -s /bin/bash sandbox

# Ensure the sandbox user owns their home
COPY --chown=sandbox:sandbox bashrc /home/sandbox/.bashrc

USER sandbox
WORKDIR /home/sandbox

# Install Claude Code as the sandbox user
RUN curl -fsSL https://claude.ai/install.sh | bash

# Set Go paths inside the container
ENV GOPATH=/home/sandbox/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
# Ensure the Claude binary is in the PATH
ENV PATH="/home/sandbox/.local/bin:${PATH}"

CMD ["/bin/bash"]
