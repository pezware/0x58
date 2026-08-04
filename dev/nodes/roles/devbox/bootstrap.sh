#!/usr/bin/env bash
# devbox role — the always-on workspace: repos, Claude Code / Codex in tmux,
# kubectl pointed at whatever k8s node happens to exist.
#
# Ordering matters: common_main joins the tailnet FIRST, so if the heavy
# provisioning below fails you can still SSH in and fix it by hand. Everything
# after the join is therefore non-fatal by design.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy
REPO_REF="${REPO_REF:-main}"

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

if first_boot; then
    # ── mosh: survives the wifi-to-cellular handover that kills plain ssh ────
    log "installing mosh"
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mosh || log "mosh install failed (non-fatal)"

    # ── Hand off to the repo's own bootstrap ────────────────────────────────
    # Deliberately the SAME entry point a human would use, so there is one code
    # path to keep working rather than a divergent cloud-init copy.
    log "running 0x58 start.sh (ref: $REPO_REF)"
    if as_user "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/pezware/0x58/$REPO_REF/linux/start.sh)\""; then
        log "0x58 restore complete"
    else
        log "0x58 restore FAILED — node is on the tailnet, finish it manually (see post_apply_steps)"
    fi

    # ── mise toolchain ──────────────────────────────────────────────────────
    # restore.sh installs mise but deliberately stops short of installing tools;
    # it prints the symlink and `mise install` as manual steps. That is right for
    # a general Linux box and wrong for this one: a devbox whose whole purpose is
    # running Claude and Codex is not a working machine without node, python and
    # go, and "rebuild in 10 minutes" is untrue if it is followed by two manual
    # commands and a 15-minute wait nobody remembers.
    #
    # Slow (~15 min for ~60 tools) but safe to be slow: common_main already
    # joined the tailnet, so the node is reachable throughout and a failure here
    # leaves a debuggable box rather than an unreachable one.
    log "linking mise config and installing toolchain (~15 min for ~60 tools)"
    as_user 'mkdir -p ~/.config/mise && ln -sfn ~/src/public/0x58/dotfiles/mise/config.toml ~/.config/mise/config.toml' \
        || log "mise config symlink failed (non-fatal)"
    as_user 'mise trust ~/.config/mise/config.toml' >/dev/null 2>&1 || true
    if as_user 'mise install'; then
        log "mise toolchain installed"
    else
        log "mise install FAILED — run 'mise install' by hand once the box is up"
    fi
fi

# ── Let rootless containers bind 80/443 (EVERY boot) ────────────────────────
# Rootless podman cannot bind below 1024, which is what actually blocked the
# compose tier — Caddy wants 80 and 443. It was misfiled as a memory problem for
# a while; it never was one.
#
# Deliberately NOT in common_sysctl, even though it is one line and every role
# would work with it. The k8s node is the box where hostile code is *supposed* to
# run, and handing unprivileged processes there the ability to bind low ports
# hands them port 53 too — a DNS-spoofing position against everything else on
# that node. The devbox earns the relaxation because nothing untrusted should be
# running on it and it has no inbound path: Tailscale-only, OpenSSH disabled,
# Cloud Firewall dropping the rest.
#
# Written as a drop-in so systemd-sysctl reapplies it at boot; the `sysctl -p` is
# only to take effect now, without waiting for a reboot.
if [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null)" != "0" ]; then
    log "allowing unprivileged binds below 1024 (rootless podman needs 80/443)"
    cat > /etc/sysctl.d/99-0x58-devbox.conf <<'SYSCTL'
# 0x58 devbox only — rootless podman must bind 80/443 for the compose tier.
net.ipv4.ip_unprivileged_port_start = 0
SYSCTL
    sysctl -p /etc/sysctl.d/99-0x58-devbox.conf >/dev/null || log "sysctl apply failed (non-fatal)"
fi

# ── A tmux session waiting to be attached (EVERY boot) ──────────────────────
# So `mosh devbox -- tmux attach -t main` works on the first connection from a
# phone rather than erroring with "no server running" — and, because tmux dies
# with the machine, so it still works after a reboot. This is the specific thing
# that made a per-boot unit necessary rather than relying on cloud-init.
if ! as_user 'tmux has-session -t main 2>/dev/null'; then
    log "creating detached tmux session 'main'"
    as_user 'tmux new-session -d -s main' || log "tmux session create failed (non-fatal)"
fi

log "devbox bootstrap done"
