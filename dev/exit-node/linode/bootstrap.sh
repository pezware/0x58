#!/usr/bin/env bash
# Idempotent. Embedded into cloud-init's runcmd; runs on first boot and every subsequent boot.
# Mirrors gcp/startup.sh — only difference is auth-key delivery (tmpfs file vs Secret Manager).
set -euo pipefail

KEY_FILE="/run/tailscale-bootstrap.key"

# ── 1. IPv4 forwarding + IPv6 fully disabled (unused on this tailnet) ────────
cat > /etc/sysctl.d/99-tailscale.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-tailscale.conf

# ── 2. Kill OpenSSH — Tailscale SSH is the only access path ──────────────────
systemctl disable --now ssh 2>/dev/null || true

# ── 3. Create arbeitandy user with GitHub SSH keys ───────────────────────────
if ! id arbeitandy &>/dev/null; then
  useradd -m -s /bin/bash arbeitandy
  echo "arbeitandy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/arbeitandy
  chmod 440 /etc/sudoers.d/arbeitandy
fi
mkdir -p /home/arbeitandy/.ssh
chmod 700 /home/arbeitandy/.ssh
# Non-fatal: a GitHub outage on a reboot must not block Tailscale reconnect.
curl -fsSL https://github.com/arbeitandy.keys > /home/arbeitandy/.ssh/authorized_keys || true
chmod 600 /home/arbeitandy/.ssh/authorized_keys
chown -R arbeitandy:arbeitandy /home/arbeitandy/.ssh

# ── 4. Install Tailscale if missing ──────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

# ── 5. Already authenticated? Just reapply settings and exit ─────────────────
if tailscale status &>/dev/null; then
  tailscale set --advertise-exit-node --ssh --accept-dns=false
  shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE" 2>/dev/null || true
  exit 0
fi

# ── 6. First boot: read auth key from tmpfs, authenticate, then shred ────────
[ -r "$KEY_FILE" ] || { echo "no auth key at $KEY_FILE" >&2; exit 1; }
AUTH_KEY=$(< "$KEY_FILE")

tailscale up \
  --authkey="$AUTH_KEY" \
  --advertise-exit-node \
  --ssh \
  --accept-dns=false

# Best-effort wipe — already on tmpfs, but be explicit so the key isn't sitting in RAM longer than needed.
shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE" 2>/dev/null || true
