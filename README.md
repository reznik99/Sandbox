# Sandbox

A secure Podman container for running untrusted scripts.

## Included tools

| Tool           | Package                |
| -------------- | ---------------------- |
| Node.js 24     | nodejs24, nodejs24-npm |
| Go             | golang                 |
| GCC/G++        | gcc, gcc-c++           |
| Make           | make                   |
| Git            | git                    |
| SSH            | openssh-clients        |
| GPG            | gnupg2                 |
| OpenSSL        | openssl                |
| curl           | curl                   |
| wget           | wget                   |
| Vim            | vim                    |
| fzf            | fzf                    |
| lsd            | lsd                    |
| ripgrep        | ripgrep                |
| find           | findutils              |
| ps/top         | procps-ng              |
| Claude Code    | claude.ai/install.sh   |

## Build the image

```bash
podman build \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t sandbox .
```

## Shell aliases

Add these to your `~/.bashrc` or `~/.profile`:

```bash
# Fully isolated sandbox (no shared host files)
sandbox() {
    local name="sandbox"
    local state
    state=$(podman inspect --format '{{.State.Status}}' "$name" 2>/dev/null)

    if [ "$state" = "running" ]; then
        podman exec -it "$name" bash
    elif [ "$state" = "exited" ]; then
        podman start "$name"
        podman exec -it "$name" bash
    else
        podman run -d \
          --name "$name" \
          --cap-drop=ALL \
          --security-opt=no-new-privileges \
          --userns=keep-id \
          --pids-limit=512 \
          --memory=2g \
          --cpus=10 \
          -v sandbox-claude:/home/sandbox/.claude \
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Sandbox with ONLY ~/Code mounted
sandbox-code() {
    local name="sandbox-code"
    local state
    state=$(podman inspect --format '{{.State.Status}}' "$name" 2>/dev/null)

    if [ "$state" = "running" ]; then
        podman exec -it "$name" bash
    elif [ "$state" = "exited" ]; then
        podman start "$name"
        podman exec -it "$name" bash
    else
        podman run -d \
          --name "$name" \
          --cap-drop=ALL \
          --security-opt=no-new-privileges \
          --userns=keep-id \
          --pids-limit=512 \
          --memory=4g \
          --cpus=10 \
          -v sandbox-claude:/home/sandbox/.claude \
          -v ~/Code:/workspace:rw,z \
          -w /workspace \
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Stop the sandbox (SIGKILL — instant; PID 1 is `sleep infinity` with nothing to flush)
alias sandbox-stop='podman kill sandbox sandbox-code'
# Destroy the sandbox (container only, image is kept)
alias sandbox-nuke='podman rm -f sandbox sandbox-code'
# Rebuild the image from scratch
alias sandbox-rebuild='podman build --no-cache -t sandbox .'
```

## Usage

```bash
# Enter the fully isolated sandbox
sandbox

# Enter the sandbox with ~/Code mounted at /workspace
sandbox-code

# Stop all sandbox containers
sandbox-stop

# Destroy all sandbox containers and start fresh next time
sandbox-nuke

# Rebuild the image (e.g. after editing the Dockerfile)
sandbox-rebuild
```

## Persistent state

Per-app state lives in named podman volumes mounted at the app's standard
path inside the container. Auth, settings, skills, and memory survive
`sandbox-nuke` and `sandbox-rebuild`; only `podman volume rm <name>` wipes them.

| Volume | Mount point | Holds |
| --- | --- | --- |
| `sandbox-claude` | `/home/sandbox/.claude` | Claude Code auth, settings, skills, memory |

First time you run `sandbox`, the volume is empty — run `claude login` once
and it's persisted from then on. Subsequent `sandbox-nuke`/`sandbox-rebuild`
keeps you logged in.

To add more persistent paths later (e.g. LazyVim plugins), add another
named volume mount to both `sandbox` and `sandbox-code` and create the
target directory in the `Dockerfile` for clean ownership.

## Security

The container runs with:

- `--cap-drop=ALL` — all Linux capabilities dropped
- `--security-opt=no-new-privileges` — prevents privilege escalation
- `--userns=keep-id` — maps host UID into the container
- `--pids-limit=512` — limits fork bombs
- `--memory=2g`/`4g` — caps memory usage
- `--cpus=10` — limits CPU usage to 10 cores
- Non-root user (`sandbox`) inside the container
