# Sandbox

A secure Podman image with three preset run profiles for sandboxed
development work — scratch (`sandbox`), AI-assisted editing (`sandbox-code`),
and dev-server (`sandbox-dev`). Designed to neutralise npm/Go supply-chain
attacks by isolating dependency execution from your host credentials.

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
# Fully isolated scratch sandbox — no host mounts, no Claude state, no ports.
# Use for running unknown/untrusted code. State is wiped by `sandbox-nuke`.
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
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Sandbox for AI-assisted editing — code mounts + Claude state, NO forwarded ports.
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

# Sandbox for running dev servers — code mounts + port forwarding, NO Claude state.
# Keeping the Claude token out of this container reduces blast radius if a
# running dev process pulls in a compromised dep.
sandbox-dev() {
    local name="sandbox-dev"
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
          -v ~/Code:/workspace:rw,z \
          -p 3000-3010:3000-3010 \
          -p 8080-8085:8080-8085 \
          -p 9229:9229 \
          -w /workspace \
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Stop all sandbox containers (SIGKILL — instant; PID 1 is `sleep infinity` with nothing to flush)
alias sandbox-stop='podman kill sandbox sandbox-code sandbox-dev 2>/dev/null'
# Destroy all sandbox containers (image and volumes are kept)
alias sandbox-nuke='podman rm -f sandbox sandbox-code sandbox-dev 2>/dev/null'
# Rebuild the image from scratch
alias sandbox-rebuild='podman build --no-cache -t sandbox .'
```

## Usage

Three sandboxes for three different jobs. Each is a separate container — you can have any combination running concurrently in different terminals.

| Command | Mounts | Ports | Use for |
| --- | --- | --- | --- |
| `sandbox` | none | none | Throwaway scratch. Running unknown code with zero credential exposure. |
| `sandbox-code` | `sandbox-claude` volume + `~/Code` at `/workspace` | none | Reading/editing code with Claude Code. |
| `sandbox-dev` | `~/Code` at `/workspace` | `3000-3010`, `8080-8085`, `9229` | Running dev servers, builds, tests. Browser on host reaches `localhost:3000` etc. No Claude token mounted, so a compromised dep can't steal it. |

```bash
sandbox          # enter the scratch sandbox
sandbox-code     # enter the code+Claude sandbox
sandbox-dev      # enter the code+ports sandbox (no Claude)

sandbox-stop     # stop all three (SIGKILL — instant)
sandbox-nuke     # destroy all three containers (volumes survive)
sandbox-rebuild  # rebuild the image from scratch
```

## Persistent state

Per-app state lives in named podman volumes mounted at the app's standard
path inside the container. Volumes survive `sandbox-nuke` and `sandbox-rebuild`;
only `podman volume rm <name>` wipes them.

| Volume | Mount point | Mounted in | Holds |
| --- | --- | --- | --- |
| `sandbox-claude` | `/home/sandbox/.claude` | `sandbox-code` only | Claude Code auth, settings, skills, memory |

The Dockerfile also baked a symlink `~/.claude.json → ~/.claude/claude.json`,
so the `~/.claude.json` file (which Claude writes at `$HOME` root, outside
`~/.claude/`) is also redirected into the volume. Together this is enough
for `claude login` to persist fully.

First time you run `sandbox-code`, the volume is empty — run `claude login`
once and it's persisted from then on. Subsequent `sandbox-nuke` /
`sandbox-rebuild` keeps you logged in.

`sandbox` and `sandbox-dev` deliberately do NOT mount the volume — they have
no business with your Claude credentials. Worms running in those containers
can't reach the token.

To add more persistent paths later (e.g. LazyVim plugins), add a named
volume mount to the relevant function(s) and create the target directory in
the `Dockerfile` so the volume inherits correct ownership on first mount.

## Security

Each container runs with:

- `--cap-drop=ALL` — all Linux capabilities dropped
- `--security-opt=no-new-privileges` — prevents privilege escalation
- `--userns=keep-id` — maps host UID into the container (rootless)
- `--pids-limit=512` — limits fork bombs
- `--memory=2g` (`sandbox`) or `4g` (`sandbox-code` / `sandbox-dev`) — caps memory
- `--cpus=10` — caps CPU usage
- Non-root user (`sandbox`) inside the container

The image also bakes in defenses against npm supply-chain attacks:

- `NPM_CONFIG_PREFIX=/home/sandbox/.local` — `npm install -g` works as the
  non-root sandbox user without touching `/usr/local`
- `NPM_CONFIG_MIN_RELEASE_AGE=2` — every `npm install` enforces a 2-day
  cooldown on newly published versions. Most fast-burn worms (Shai-Hulud
  style) are detected and yanked within hours, so the cooldown skips over
  them entirely. Override per command with `npm install --min-release-age=0 <pkg>`
  when you actually need a freshly published version.
- npm is self-upgraded to ≥ 11.10.0 during build (Fedora ships 11.8.0, which
  predates the `min-release-age` setting).
