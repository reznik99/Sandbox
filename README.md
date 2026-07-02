# Sandbox

A secure Podman image with two preset run profiles for sandboxed
development work — scratch (`sandbox`) and AI-assisted editing
(`sandbox-code`). Designed to neutralise npm/Go supply-chain attacks
by isolating dependency execution from your host credentials.

## Included tools

| Tool           | Source                          |
| -------------- | ------------------------------- |
| Node.js 24 LTS | nodejs.org (tarball)            |
| Go             | go.dev (tarball)                |
| GCC/G++        | gcc, gcc-c++                    |
| Make           | make                   |
| Git            | git                    |
| SSH            | openssh-clients        |
| GPG            | gnupg2                 |
| OpenSSL        | openssl                |
| curl           | curl                   |
| wget           | wget                   |
| Neovim         | neovim                 |
| Vim            | vim                    |
| fzf            | fzf                    |
| lsd            | lsd                    |
| ripgrep        | ripgrep                |
| fd             | fd-find                |
| find           | findutils              |
| ps/top         | procps-ng              |
| Claude Code    | @anthropic-ai/claude-code (npm) |
| Codex CLI      | @openai/codex (npm)             |
| OpenCode       | opencode-ai (npm)               |

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
          --init \
          --cap-drop=ALL \
          --security-opt=no-new-privileges \
          --userns=keep-id \
          --pids-limit=512 \
          --memory=2g \
          --cpus=10 \
          --tmpfs /tmp:rw,noexec,nosuid,size=4g \
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Sandbox for AI-assisted editing — code mounts + AI agent state + nvim, NO forwarded ports.
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
          --init \
          --cap-drop=ALL \
          --security-opt=no-new-privileges \
          --userns=keep-id \
          --pids-limit=512 \
          --memory=4g \
          --cpus=10 \
          --tmpfs /tmp:rw,nosuid,size=4g \
          -v sandbox-claude:/home/sandbox/.claude \
          -v sandbox-codex:/home/sandbox/.codex \
          -v sandbox-opencode-data:/home/sandbox/.local/share/opencode \
          -v sandbox-opencode-config:/home/sandbox/.config/opencode \
          -v sandbox-nvim-share:/home/sandbox/.local/share/nvim \
          -v sandbox-nvim-state:/home/sandbox/.local/state/nvim \
          -v ~/.config/nvim:/home/sandbox/.config/nvim:ro,z \
          -v ~/Code:/workspace:rw,z \
          -w /workspace \
          localhost/sandbox sleep infinity
        podman exec -it "$name" bash
    fi
}

# Stop all sandbox containers. `--ignore` skips containers that don't exist;
# `-t 0` is effectively instant (PID 1 is `sleep infinity` so nothing to flush).
alias sandbox-stop='podman stop -t 0 --ignore sandbox sandbox-code'
# Destroy all sandbox containers (image and volumes are kept).
alias sandbox-nuke='podman rm -f --ignore sandbox sandbox-code'
# Rebuild the image from scratch
alias sandbox-rebuild='podman build --no-cache -t sandbox .'
```

## Usage

Two sandboxes for two different jobs. Each is a separate container — you can have both running concurrently in different terminals.

| Command | Mounts | Ports | Use for |
| --- | --- | --- | --- |
| `sandbox` | none | none | Throwaway scratch. Running unknown code with zero credential exposure. |
| `sandbox-code` | `sandbox-claude` + `sandbox-codex` + `sandbox-opencode-*` volumes + `~/Code` at `/workspace` + `~/.config/nvim` read-only | none | Reading/editing code with Claude Code, Codex CLI, or OpenCode. |

```bash
sandbox          # enter the scratch sandbox
sandbox-code     # enter the code+AI sandbox

sandbox-stop     # stop all sandboxes (SIGKILL — instant)
sandbox-nuke     # destroy all sandboxes (volumes survive)
sandbox-rebuild  # rebuild the image from scratch
```

## Persistent state

Per-app state lives in named podman volumes mounted at the app's standard
path inside the container. Volumes survive `sandbox-nuke` and `sandbox-rebuild`;
only `podman volume rm <name>` wipes them.

| Volume | Mount point | Mounted in | Holds |
| --- | --- | --- | --- |
| `sandbox-claude` | `/home/sandbox/.claude` | `sandbox-code` only | Claude Code auth, settings, skills, memory |
| `sandbox-codex` | `/home/sandbox/.codex` | `sandbox-code` only | Codex CLI auth, config, sessions, memories, plus `~/.agents/` content via symlink |
| `sandbox-opencode-data` | `/home/sandbox/.local/share/opencode` | `sandbox-code` only | OpenCode provider credentials, including `auth.json` |
| `sandbox-opencode-config` | `/home/sandbox/.config/opencode` | `sandbox-code` only | OpenCode global config, including `opencode.json` and `tui.json` |

The Dockerfile bakes two symlinks that redirect host-style paths into the
named volumes so writes persist transparently:

- `~/.claude.json → ~/.claude/claude.json` — Claude writes this file at
  `$HOME` root (outside `~/.claude/`); the symlink redirects it back inside
  the volume. Claude uses `open()/write()/close()` (not atomic-rename) so
  the symlink survives.
- `~/.agents → ~/.codex/agents` — `~/.agents/` is the shared agent skill
  location read by Codex (and originally Claude). It physically lives
  inside the Codex volume, so a single volume holds everything Codex needs.

First time you run `sandbox-code`, the volumes are empty — run `claude login`,
`codex login`, and `opencode` then `/connect` once and they're persisted from then on. Subsequent
`sandbox-nuke` / `sandbox-rebuild` keeps you logged in.

`sandbox` deliberately does NOT mount the Claude/Codex/OpenCode volumes — it has no
business with your credentials. Worms running in that container can't reach
the token.

To add more persistent paths later (e.g. LazyVim plugins), add a named
volume mount to the relevant function(s) and create the target directory in
the `Dockerfile` so the volume inherits correct ownership on first mount.

## Security

Each container runs with:

- `--cap-drop=ALL` — all Linux capabilities dropped
- `--security-opt=no-new-privileges` — prevents privilege escalation
- `--userns=keep-id` — maps host UID into the container (rootless)
- `--pids-limit=512` — limits fork bombs
- `--memory=2g` (`sandbox`) or `4g` (`sandbox-code`) — caps memory
- `--cpus=10` — caps CPU usage
- `sandbox` uses `--tmpfs /tmp:rw,noexec,nosuid,size=4g` — `/tmp` is
  non-executable, blocking the "drop payload, chmod +x, exec" pattern common
  in npm/Go worms
- `sandbox-code` uses `--tmpfs /tmp:rw,nosuid,size=4g` — OpenCode needs an
  executable temp directory during startup, so the noexec hardening is reserved
  for the fully isolated scratch sandbox
- `--init` — proper PID 1 reaps zombies (matters for long-lived sessions)
- Non-root user (`sandbox`) inside the container
- `~/.config/nvim` mounted read-only in `sandbox-code` — a compromised dep
  can't rewrite your host nvim config (which executes when you open nvim
  outside the container)

The image also bakes in defenses against npm supply-chain attacks:

- `NPM_CONFIG_PREFIX=/home/sandbox/.local` — `npm install -g` works as the
  non-root sandbox user without touching `/usr/local`
- `NPM_CONFIG_MIN_RELEASE_AGE=3` — every `npm install` enforces a 3-day
  cooldown on newly published versions. Most fast-burn worms (Shai-Hulud
  style) are detected and yanked within hours, so the cooldown skips over
  them entirely. Override per command with `npm install --min-release-age=0 <pkg>`
  when you actually need a freshly published version.
- npm is self-upgraded to the latest release during build, keeping it ahead
  of the version bundled with Node.
