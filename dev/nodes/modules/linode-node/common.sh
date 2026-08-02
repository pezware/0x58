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

# ROLE, TS_TAG, TS_EXTRA_FLAGS, SWAP_MB, VOLUME_* — written by cloud-init.
# shellcheck disable=SC1090
[ -r "$NODE_ENV" ] && . "$NODE_ENV"
: "${ROLE:=unknown}" "${TS_TAG:=}" "${TS_EXTRA_FLAGS:=}" "${SWAP_MB:=0}"
: "${VOLUME_LABEL:=}" "${VOLUME_MOUNT:=}"

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

# ── /etc/hosts entry for our own hostname ───────────────────────────────────
# cloud-init sets the hostname but leaves /etc/hosts alone, so every sudo prints
# "unable to resolve host <name>". Cosmetic, but it appears on EVERY privileged
# command, and output that is always noise is output you stop reading — which is
# a poor habit on the box where sudo actually matters. 127.0.1.1 is the Debian
# convention for a machine's own name, kept distinct from localhost.
common_hostname() {
    local h
    h=$(hostname)
    [ -n "$h" ] || return 0
    grep -qE "^127\.0\.1\.1[[:space:]]+${h}([[:space:]]|\$)" /etc/hosts \
        || printf '127.0.1.1\t%s\n' "$h" >> /etc/hosts
}

# ── Persistent Block Storage volume ─────────────────────────────────────────
# Formats ONLY if the device has no filesystem, so a rebuilt node re-attaching an
# existing volume keeps its data. That check is the whole safety property here:
# an unconditional mkfs would silently destroy every working tree on rebuild.
common_volume() {
    [ -n "$VOLUME_LABEL" ] && [ -n "$VOLUME_MOUNT" ] || return 0

    local dev="/dev/disk/by-id/scsi-0Linode_Volume_${VOLUME_LABEL}"
    # Attachment can lag the first boot; wait rather than silently skipping.
    local waited=0
    while [ ! -e "$dev" ] && [ "$waited" -lt 60 ]; do
        sleep 2
        waited=$((waited + 2))
    done
    if [ ! -e "$dev" ]; then
        log "volume $VOLUME_LABEL never appeared at $dev — skipping mount"
        return 0
    fi

    if ! blkid "$dev" >/dev/null 2>&1; then
        log "volume is blank — creating ext4 (first use)"
        mkfs.ext4 -L "${VOLUME_LABEL:0:16}" "$dev" >/dev/null
    else
        log "volume already has a filesystem — preserving it"
    fi

    mkdir -p "$VOLUME_MOUNT"

    # Mounting over a POPULATED directory hides its contents instead of failing,
    # so data written before the volume existed silently vanishes from view and
    # looks lost. Seen for real: a node whose volume creation failed cloned the
    # repo to the root disk, and attaching the volume later shadowed it.
    # Mount anyway — the volume is the intended state — but say plainly where the
    # shadowed data went, because nothing else will.
    if ! mountpoint -q "$VOLUME_MOUNT" && [ -n "$(ls -A "$VOLUME_MOUNT" 2>/dev/null)" ]; then
        log "WARNING: $VOLUME_MOUNT is not empty; mounting will hide its current contents"
        log "         recover with:  mkdir -p /tmp/rootview && mount --bind / /tmp/rootview"
        log "         then look in:  /tmp/rootview$VOLUME_MOUNT"
    fi

    # nofail: a missing volume must not wedge boot into emergency mode on a box
    # whose only access path comes up later in the boot sequence.
    grep -q " $VOLUME_MOUNT " /etc/fstab \
        || echo "$dev $VOLUME_MOUNT ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
    mountpoint -q "$VOLUME_MOUNT" || mount "$VOLUME_MOUNT"
    chown arbeitandy:arbeitandy "$VOLUME_MOUNT"
    log "volume mounted at $VOLUME_MOUNT ($(df -h --output=size "$VOLUME_MOUNT" | tail -1 | tr -d ' '))"
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

    # Advertise the tag EXPLICITLY rather than trusting the auth key to carry it.
    # An untagged key silently yields a USER-owned node: every ACL rule written
    # against tag:<role> then fails to match, and — the part that bites months
    # later — the node gets a key expiry, since only tag-owned nodes are exempt.
    # Passing it here makes the tag a property of the code, not of how someone
    # happened to click through the key-creation form.
    local tag_flag=()
    [ -n "$TS_TAG" ] && tag_flag=(--advertise-tags="$TS_TAG")

    log "joining tailnet as ${TS_TAG:-<untagged>}"
    # file: form keeps the key out of the process argument vector, where any
    # local process could read it from /proc/<pid>/cmdline while `up` runs.
    # shellcheck disable=SC2086
    tailscale up \
        --auth-key="file:$KEY_FILE" \
        --hostname="$(hostname)" \
        "${tag_flag[@]}" \
        --ssh --accept-dns=false $TS_EXTRA_FLAGS
}

common_main() {
    log "bootstrap starting"
    common_sysctl
    common_hostname
    common_disable_openssh
    common_user
    # After common_user: the mount point lives inside the home directory it creates.
    common_volume
    common_swap
    common_install_perboot_unit
    common_tailscale
    wipe_key
    log "common bootstrap done"
}
