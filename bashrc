# lsd replaces ls
alias ll='lsd -l'
alias la='lsd -la'
alias lt='lsd --tree'

# fzf keybindings and completion
eval "$(fzf --bash)"

# Advertise 24-bit color so Claude/Codex render brand accents (orange throbber,
# purple slash-menu highlight) instead of downsampling to the 16-color palette.
# podman exec -t forwards TERM but not COLORTERM, so we set it here.
export COLORTERM=truecolor

# Prompt
PS1='\[\e[1;33m\][sandbox]\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \$ '

# Tab/window title — "sandbox: <pwd>" updates on every prompt as you `cd`.
# OSC 0 sets icon+window title; works in every modern terminal.
PROMPT_COMMAND='printf "\033]0;sandbox: %s\007" "${PWD/#$HOME/~}"'

# /tmp is mounted noexec for security, but Go writes test binaries there and
# tries to execute them. Redirect TMPDIR to ~/.cache so `go test` works.
export TMPDIR="$HOME/.cache/go-tmp"
mkdir -p "$TMPDIR"

# Background tint — subtle warm-brown to pair with the yellow [sandbox] prompt
# and make this terminal visually distinct from the host. OSC 11 sets bg;
# OSC 111 resets on shell exit so the host terminal returns to normal.
# Silently ignored by terminals that don't support OSC 11 (older gnome-terminal,
# macOS Terminal.app) — safe to set unconditionally.
printf '\033]11;#1a1410\007'
trap 'printf "\033]111\007"' EXIT
