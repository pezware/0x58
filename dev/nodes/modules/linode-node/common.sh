#!/usr/bin/env bash
# Shared node bootstrap — sourced by every role's /usr/local/sbin/node-bootstrap.
#
# TWO invocation modes:
#   node-bootstrap              first boot, via cloud-init runcmd — full provisioning
#   node-bootstrap --per-boot   every boot, via 0x58-node-boot.service — light reconcile
#
# The split exists because cloud-init's runcmd is once-per-INSTANCE, not
# once-per-boot: the scripts-user module defaults to that frequency, so a reboot
# never re-runs it. Anything that must survive a reboot needs the systemd unit
# installed by common_install_perboot_unit.
set -euo pipefail

KEY_FILE="/run/tailscale-bootstrap.key"
NODE_ENV="/etc/0x58-node.env"
PERBOOT_UNIT="0x58-node-boot.service"

# ── Credential cleanup, armed immediately ───────────────────────────────────
# Registered before anything can fail. Without this, an error in sysctl, user
# creation, swap, or `tailscale up` exits under set -e and strands the auth key
# in /run until the next reboot.
wipe_key() { shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE" 2>/dev/null || true; }
trap wipe_key EXIT

# ROLE, TS_TAG, TS_EXTRA_FLAGS, SWAP_MB — written by cloud-init from terraform.
# shellcheck disable=SC1090
[ -r "$NODE_ENV" ] && . "$NODE_ENV"
: "${ROLE:=unknown}" "${TS_TAG:=}" "${TS_EXTRA_FLAGS:=}" "${SWAP_MB:=0}"

# Mode flag — positional params are inherited from the sourcing script.
PER_BOOT=0
[ "${1:-}" = "--per-boot" ] && PER_BOOT=1

first_boot() { [ "$PER_BOOT" -eq 0 ]; }

log() { printf '[0x58/%s%s] %s\n' "$ROLE" "$( ((PER_BOOT)) && printf ':per-boot')" "$*"; }

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
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q '^/swapfile$'; then
        return 0
    fi
    if [ ! -f /swapfile ]; then
        log "creating ${SWAP_MB}MB swapfile"
        fallocate -l "${SWAP_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB"
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
    fi
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

# ── Per-boot reconcile unit ─────────────────────────────────────────────────
# What actually survives reboots. Kept deliberately light: it re-runs the role
# script in --per-boot mode, which skips package installs and cluster creation.
common_install_perboot_unit() {
    local unit="/etc/systemd/system/$PERBOOT_UNIT" tmp
    tmp=$(mktemp)
    cat > "$tmp" <<UNIT
[Unit]
Description=0x58 node per-boot reconcile (${ROLE})
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/node-bootstrap --per-boot

[Install]
WantedBy=multi-user.target
UNIT
    if ! cmp -s "$tmp" "$unit"; then
        install -m 644 "$tmp" "$unit"
        systemctl daemon-reload
    fi
    rm -f "$tmp"
    systemctl enable "$PERBOOT_UNIT" >/dev/null 2>&1 || true
}

# ── Tailscale: install, authenticate on first boot, reapply flags after ─────
common_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    systemctl enable --now tailscaled

    # TS_EXTRA_FLAGS is quoted in the env file but intentionally word-split here.
    # shellcheck disable=SC2086
    if tailscale status &>/dev/null; then
        log "already authenticated — reapplying flags"
        tailscale set --ssh --accept-dns=false $TS_EXTRA_FLAGS
        return
    fi

    [ -r "$KEY_FILE" ] || { echo "no auth key at $KEY_FILE" >&2; return 1; }
    log "joining tailnet as $TS_TAG"
    # file: form keeps the key out of the process argument vector, where any
    # local process could read it from /proc/<pid>/cmdline while `up` runs.
    # shellcheck disable=SC2086
    tailscale up \
        --auth-key="file:$KEY_FILE" \
        --hostname="$(hostname)" \
        --ssh --accept-dns=false $TS_EXTRA_FLAGS
}

common_main() {
    log "bootstrap starting"
    common_sysctl
    common_disable_openssh
    common_user
    common_swap
    common_install_perboot_unit
    common_tailscale
    wipe_key
    log "common bootstrap done"
}
