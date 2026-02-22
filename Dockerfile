FROM fedora:latest

RUN dnf upgrade -y --refresh && \
    dnf install -y \
        nodejs24 \
        nodejs24-npm \
        golang \
        openssh-clients \
        git \
        fzf \
        lsd \
        gnupg2 \
        openssl \
        curl \
        wget \
        vim \
        findutils \
        procps-ng \
        && \
    dnf clean all && \
    rm -rf /var/cache/dnf

RUN useradd -m -s /bin/bash sandbox

COPY --chown=sandbox:sandbox bashrc /home/sandbox/.bashrc

USER sandbox
WORKDIR /home/sandbox

CMD ["/bin/bash"]
