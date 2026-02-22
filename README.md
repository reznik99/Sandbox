# Sandbox

A secure Podman container for running untrusted scripts.

## Included tools

| Tool       | Package            |
| ---------- | ------------------ |
| Node.js 24 | nodejs24, nodejs24-npm |
| Go         | golang             |
| SSH        | openssh-clients    |
| Git        | git                |
| fzf        | fzf                |
| lsd        | lsd                |
| GPG        | gnupg2             |

## Build the image

```bash
podman build -t sandbox .
```

## Shell aliases

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# Start an existing sandbox or create a new one
alias sandbox='podman start -ai sandbox 2>/dev/null || \
podman run -it \
  --name sandbox \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --pids-limit=512 \
  --memory=2g \
  --cpus=10 \
  localhost/sandbox bash'

# Stop the sandbox
alias sandbox-stop='podman stop sandbox'

# Destroy the sandbox (container only, image is kept)
alias sandbox-nuke='podman rm -f sandbox'

# Rebuild the image from scratch
alias sandbox-rebuild='podman build --no-cache -t sandbox .'
```

## Usage

```bash
# Enter the sandbox (creates container on first run, reattaches on subsequent runs)
sandbox

# Stop the sandbox
sandbox-stop

# Destroy the container and start fresh next time
sandbox-nuke

# Rebuild the image (e.g. after editing the Dockerfile)
sandbox-rebuild
```

## Security

The container runs with:

- `--cap-drop=ALL` — all Linux capabilities dropped
- `--security-opt=no-new-privileges` — prevents privilege escalation
- `--pids-limit=512` — limits fork bombs
- `--memory=2g` — caps memory usage
- `--cpus=10` — limits CPU usage to 10 cores (half of available)
- Non-root user (`sandbox`) inside the container
