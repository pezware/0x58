#!/usr/bin/env bash
# Idempotent. Runs on every boot (fresh VM and start/stop cycles).
set -euo pipefail

METADATA="http://metadata.google.internal/computeMetadata/v1"

meta() { curl -sf -H "Metadata-Flavor: Google" "${METADATA}/$1"; }

# ── 1. IP forwarding — required for exit node to route traffic ────────────────
# Write to sysctl.d so it persists AND applies immediately (Tailscale checks the file)
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
  > /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# ── 2. Align OS hostname with Tailscale node name ────────────────────────────
hostnamectl set-hostname pezware-tres

# ── 3. Kill OpenSSH — Tailscale SSH is the only access path ──────────────────
systemctl disable --now ssh 2>/dev/null || true

# ── 4. Create arbeitandy user with GitHub SSH keys ────────────────────────────
if ! id arbeitandy &>/dev/null; then
  useradd -m -s /bin/bash arbeitandy
  echo "arbeitandy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/arbeitandy
  chmod 440 /etc/sudoers.d/arbeitandy
fi
mkdir -p /home/arbeitandy/.ssh
chmod 700 /home/arbeitandy/.ssh
# Non-fatal: a GitHub outage on a spot-preempted reboot must not block Tailscale reconnect.
curl -fsSL https://github.com/arbeitandy.keys > /home/arbeitandy/.ssh/authorized_keys || true
chmod 600 /home/arbeitandy/.ssh/authorized_keys
chown -R arbeitandy:arbeitandy /home/arbeitandy/.ssh

# ── 5. Install Tailscale if missing ──────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

# ── 6. If already authenticated (start/stop cycle), just reapply settings ────
if tailscale status &>/dev/null; then
  tailscale set --advertise-exit-node --ssh --accept-dns=false
  exit 0
fi

# ── 7. First boot: fetch auth key from Secret Manager via metadata token ──────
PROJECT=$(meta project/project-id)

TOKEN=$(meta instance/service-accounts/default/token \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

AUTH_KEY=$(curl -sf \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/tailscale-exit-auth-key/versions/latest:access" \
  | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode().strip())")

# ── 8. Authenticate and advertise as exit node ────────────────────────────────
tailscale up \
  --authkey="${AUTH_KEY}" \
  --advertise-exit-node \
  --ssh \
  --hostname=pezware-tres \
  --accept-dns=false
