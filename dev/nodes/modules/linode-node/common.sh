#!/usr/bin/env bash
# Shared node bootstrap — sourced by every role's /usr/local/sbin/node-bootstrap.
#
# Runs on first boot AND every subsequent boot (cloud-init runcmd), so every
# function here must be idempotent. Generalised from dev/exit-node/linode/bootstrap.sh,
# which remains the canonical reference for the exit-node-only case.
set -euo pipefail

KEY_FILE="/run/tailscale-bootstrap.key"
NODE_ENV="/etc/0x58-node.env"

# ROLE, TS_TAG, TS_EXTRA_FLAGS, SWAP_MB — written by cloud-init from terraform.
# shellcheck disable=SC1090
[ -r "$NODE_ENV" ] && . "$NODE_ENV"
: "${ROLE:=unknown}" "${TS_TAG:=}" "${TS_EXTRA_FLAGS:=}" "${SWAP_MB:=0}"

log() { printf '[0x58/%s] %s\n' "$ROLE" "$*"; }

# ── Kernel: forwarding is needed by docker/kind bridges and by exit nodes ────
common_sysctl() {
    cat > /etc/sysctl.d/99-0x58.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
SYSCTL
    sysctl -p /etc/sysctl.d/99-0x58.conf >/dev/null
}

# ── Kill OpenSSH: Tailscale SSH is the only access path ─────────────────────
# The Cloud Firewall already drops all inbound, so a listening sshd would be
# unreachable anyway — disabling it removes the surface entirely.
common_disable_openssh() {
    systemctl disable --now ssh 2>/dev/null || true
}

# ── User with GitHub-published SSH keys ─────────────────────────────────────
common_user() {
    local user=arbeitandy
    if ! id "$user" &>/dev/null; then
        useradd -m -s /bin/bash "$user"
        echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
        chmod 440 "/etc/sudoers.d/$user"
    fi
    install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
    # Non-fatal: a GitHub outage on reboot must not block the Tailscale reconnect.
    if curl -fsSL https://github.com/arbeitandy.keys > /tmp/gh.keys 2>/dev/null; then
        install -m 600 -o "$user" -g "$user" /tmp/gh.keys "/home/$user/.ssh/authorized_keys"
        rm -f /tmp/gh.keys
    fi
}

# ── Swapfile — stretches a small devbox; MUST stay 0 on k8s nodes ───────────
common_swap() {
    [ "${SWAP_MB:-0}" -gt 0 ] || return 0
    if swapon --show=NAME --noheadings | grep -q '^/swapfile$'; then
        log "swap already active"
        return 0
    fi
    log "creating ${SWAP_MB}MB swapfile"
    fallocate -l "${SWAP_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB"
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

# ── Tailscale: install, authenticate on first boot, reapply flags after ─────
common_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    systemctl enable --now tailscaled

    # shellcheck disable=SC2086  # TS_EXTRA_FLAGS is intentionally word-split
    if tailscale status &>/dev/null; then
        log "already authenticated — reapplying flags"
        tailscale set --ssh --accept-dns=false $TS_EXTRA_FLAGS
    else
        [ -r "$KEY_FILE" ] || { echo "no auth key at $KEY_FILE" >&2; exit 1; }
        log "first boot — joining tailnet as $TS_TAG"
        tailscale up \
            --authkey="$(< "$KEY_FILE")" \
            --hostname="$(hostname)" \
            --ssh --accept-dns=false $TS_EXTRA_FLAGS
    fi

    # Key lives on tmpfs already; shred anyway so it is not resident any longer
    # than the join requires.
    shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE" 2>/dev/null || true
}

common_main() {
    log "bootstrap starting"
    common_sysctl
    common_disable_openssh
    common_user
    common_swap
    common_tailscale
    log "common bootstrap done"
}
