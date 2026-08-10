# Linux (devbox) specific configuration
#
# OWNED BY THE DEVBOX. Sourced from the shared ~/.bashrc, which is installed
# verbatim on both machines and must stay platform-neutral. The Mac never has
# this file, which is the point: inventory.sh runs only on the Mac and copies
# ~/.bash/* into the repo, so a file that does not exist there cannot be
# clobbered by a routine sync. That is exactly how 79 lines of this content were
# silently deleted once before.
#
# Its counterpart is bash/macos.bash. Where the two make OPPOSITE choices, the
# reasoning is written on both sides — read them together.

# --- Completions -------------------------------------------------------------
[ -f "/usr/share/bash-completion/bash_completion" ] && . "/usr/share/bash-completion/bash_completion"
[ -f "/usr/local/bin/eksctl" ] && source <(eksctl completion bash)
[ -f "$HOME/.local/share/bash-completion/completions/deno.bash" ] && source "$HOME/.local/share/bash-completion/completions/deno.bash"

# --- SSH agent ---------------------------------------------------------------
# Counterpart: macos.bash pins SSH_AUTH_SOCK to the Secretive socket. Here we
# leave a forwarded agent alone — that is what lets this box sign and push with
# the Mac's Secure Enclave key, Touch-ID gated, without any private key ever
# reaching it. Pinning would clobber the forwarded agent and silently break
# git-over-SSH after `ssh -A`.
#
# ...but pin every shell to a STABLE path. The forwarded socket lives at a
# per-connection path (/tmp/auth-agentNNNN/listener.sock) that dies with the
# connection, so a tmux pane created during one session holds a dead path the
# next time you attach, and sign-push then refuses with "no SSH agent keys".
# Re-pointing one symlink means long-lived panes keep working across reconnects
# without their environment ever being touched: the target moves underneath them.
# Fix the indirection rather than chase the value.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ] \
   && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/agent.sock" ]; then
    mkdir -p "$HOME/.ssh" && ln -sfn "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
fi
# -S follows the symlink, so a dangling one is simply not adopted.
if [ -S "$HOME/.ssh/agent.sock" ]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
fi

# --- Environment -------------------------------------------------------------
export PNPM_HOME="$HOME/.local/share/pnpm"

# The per-boot unit creates the tmux session via `sudo -u`, which has no login
# session and therefore no XDG_RUNTIME_DIR. Every shell inside that session then
# fails `systemctl --user` with "Failed to connect to user scope bus" — which
# reads like systemd is broken rather than like a missing env var. Set it when
# absent; systemd --user is already running under this uid.
#
# restore.sh depends on this fallback existing.
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

# Rootless podman speaks the Docker API on a socket under the user runtime dir,
# which is what testcontainers-go probes for via DOCKER_HOST. Ryuk, its reaper
# sidecar, wants to watch the engine from a privileged container that rootless
# podman will not grant, so turn it off and let podman reap.
#
# Set only when the socket is actually there. Exporting DOCKER_HOST to a path
# that does not exist is worse than leaving it unset: testcontainers then reports
# a connection failure to a specific socket instead of its far clearer "could not
# find a valid Docker environment".
if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock" ]; then
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
    export TESTCONTAINERS_RYUK_DISABLED=true
fi

# Counterpart: macos.bash sets DO_NOT_TRACK=1. It is 0 here and only here,
# because it disables the feature-flag evaluation Claude Code's Remote Control
# depends on, and the phone path lives on this box. The Mac's privacy posture
# should not change as a side effect of enabling it.
export DO_NOT_TRACK=0
