#!/usr/bin/env bash
# exit-dev: remote dev box provisioner.
# Idempotent — runs on every boot: a fresh VM and every spot stop/start cycle.
# First boot installs the full toolchain (~3-5 min). Later boots take the fast
# path: tools are already on the (persistent) boot disk, so installs are skipped.
set -euo pipefail

METADATA="http://metadata.google.internal/computeMetadata/v1"
meta() { curl -sf -H "Metadata-Flavor: Google" "${METADATA}/$1"; }

# ── Pinned tool versions — bump these to upgrade the toolchain ───────────────
# Kept in sync with the local mise toolset (dev/.mise.toml or equivalent).
KIND_VERSION="0.31.0"
KUBECTL_VERSION="1.35.4" # track the kind node's Kubernetes version
HELM_VERSION="4.1.4"
TASK_VERSION="3.48.0"
GO_VERSION="1.26.3"
NODE_MAJOR="22"

DEV_USER="arbeitandy"
HOSTNAME_TS="$(meta attributes/dev-hostname || echo pezware-dev)"
GITHUB_USER="$(meta attributes/github-user || echo arbeitandy)"
DATA_DISK="/dev/disk/by-id/google-exit-dev-data"
DATA_MNT="/mnt/data"
HOME_DIR="${DATA_MNT}/home/${DEV_USER}"

# ── 1. Kernel tunables for a heavy kind cluster (Istio + 20+ pods) ───────────
# kind nodes share the host kernel; many pods exhaust the default inotify
# limits, which surfaces as pods stuck or controllers silently not reconciling.
cat > /etc/sysctl.d/99-exit-dev.conf <<'SYSCTL'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
SYSCTL
sysctl -p /etc/sysctl.d/99-exit-dev.conf

# ── 2. Hostname + lock access down to Tailscale SSH only ─────────────────────
hostnamectl set-hostname "${HOSTNAME_TS}"
systemctl disable --now ssh 2>/dev/null || true

# ── 3. Mount the persistent data disk (repos + Docker image cache) ───────────
if [ -b "${DATA_DISK}" ]; then
  if ! blkid "${DATA_DISK}" &>/dev/null; then
    mkfs.ext4 -m 0 -L exit-dev-data "${DATA_DISK}"
  fi
  mkdir -p "${DATA_MNT}"
  mountpoint -q "${DATA_MNT}" || mount "${DATA_DISK}" "${DATA_MNT}"
  grep -q "${DATA_MNT}" /etc/fstab || \
    echo "LABEL=exit-dev-data ${DATA_MNT} ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi
mkdir -p "${DATA_MNT}/docker" "${HOME_DIR}"

# ── 4. Dev user — home lives on the data disk so repos persist rebuilds ──────
if ! id "${DEV_USER}" &>/dev/null; then
  useradd -m -d "${HOME_DIR}" -s /bin/bash "${DEV_USER}"
  echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEV_USER}"
  chmod 440 "/etc/sudoers.d/${DEV_USER}"
fi
mkdir -p "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"
# Non-fatal: a GitHub outage on a spot-preempted reboot must not block boot.
curl -fsSL "https://github.com/${GITHUB_USER}.keys" > "${HOME_DIR}/.ssh/authorized_keys" || true
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
chown -R "${DEV_USER}:${DEV_USER}" "${HOME_DIR}"

# ── 5. Base packages ─────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl git jq tmux build-essential apt-transport-https gnupg

# ── 6. Docker — image cache on the data disk via data-root ───────────────────
if ! command -v docker &>/dev/null; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<JSON
{
  "data-root": "${DATA_MNT}/docker"
}
JSON
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "${DEV_USER}"
systemctl enable --now docker

# ── 7. Kubernetes toolchain (pinned) ─────────────────────────────────────────
if ! command -v kind &>/dev/null; then
  curl -fsSLo /usr/local/bin/kind \
    "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64"
  chmod +x /usr/local/bin/kind
fi
if ! command -v kubectl &>/dev/null; then
  curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
if ! command -v helm &>/dev/null; then
  curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C /tmp
  install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
fi
if ! command -v task &>/dev/null; then
  curl -fsSL https://taskfile.dev/install.sh | sh -s -- -b /usr/local/bin "v${TASK_VERSION}"
fi

# ── 8. Go ────────────────────────────────────────────────────────────────────
if [ ! -x /usr/local/go/bin/go ]; then
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local
fi

# ── 9. Google Cloud CLI + GKE auth plugin ────────────────────────────────────
# The work cluster's kubeconfig uses gke-gcloud-auth-plugin; gcloud also backs
# the `dev-secrets` helper and the repo backup.
if ! command -v gcloud &>/dev/null; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt-get update -y
  apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin
fi

# ── 10. Node.js + agent CLIs ─────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi
# Agent CLIs — non-fatal so a transient npm hiccup never blocks Tailscale.
npm install -g @anthropic-ai/claude-code @openai/codex || true

# ── 11. Add your own tools below ─────────────────────────────────────────────
# This block is the reproducible "image definition" — pin versions here.
# e.g. apt-get install -y ripgrep fd-find bat   # personal CLI tools

# ── 12. Login-shell PATH ─────────────────────────────────────────────────────
cat > /etc/profile.d/exit-dev.sh <<'PROFILE'
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
PROFILE

# ── 13. dev-secrets — pull a secret into the shell env, never onto disk ──────
cat > /usr/local/bin/dev-secrets <<'HELPER'
#!/usr/bin/env bash
# Print a Secret Manager secret. Usage: export ANTHROPIC_API_KEY=$(dev-secrets exit-dev-anthropic-api-key)
set -euo pipefail
exec gcloud secrets versions access latest --secret="${1:?usage: dev-secrets <secret-id>}"
HELPER
chmod +x /usr/local/bin/dev-secrets

# ── 14. Idle auto-shutdown — caps spot compute cost ──────────────────────────
# Stops the VM when nobody is connected AND the box is quiet. A running agent
# keeps the 15-min load average up, so in-flight work is not interrupted.
# Escape hatch: `sudo touch /run/dev-keepalive` (cleared on reboot).
cat > /usr/local/bin/dev-idle-check <<'IDLE'
#!/usr/bin/env bash
set -euo pipefail
[ -f /run/dev-keepalive ] && exit 0
who | grep -q . && exit 0
load15=$(awk '{print $3}' /proc/loadavg)
awk -v l="$load15" 'BEGIN { exit !(l < 0.3) }' || exit 0
logger -t dev-idle "no users, 15-min load ${load15} < 0.3 — stopping instance"
shutdown -h now
IDLE
chmod +x /usr/local/bin/dev-idle-check

cat > /etc/systemd/system/dev-idle.service <<'UNIT'
[Unit]
Description=exit-dev idle auto-shutdown check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/dev-idle-check
UNIT
cat > /etc/systemd/system/dev-idle.timer <<'UNIT'
[Unit]
Description=Run exit-dev idle check every 10 minutes
[Timer]
OnBootSec=20min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
UNIT

# ── 15. Daily repo backup to GCS (disaster-recovery snapshot) ────────────────
cat > /usr/local/bin/dev-backup <<'BACKUP'
#!/usr/bin/env bash
# rsync the dev user's repos to the GCS backup bucket.
# Source is home-relative, set by the `backup_src` Terraform variable.
set -euo pipefail
md() { curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
BUCKET=$(md backup-bucket || true)
SRC_REL=$(md backup-src || echo src)
[ -n "${BUCKET}" ] || exit 0
SRC="${HOME}/${SRC_REL}"
[ -d "${SRC}" ] || exit 0
gcloud storage rsync --recursive "${SRC}" "gs://${BUCKET}/${SRC_REL}"
BACKUP
chmod +x /usr/local/bin/dev-backup

cat > /etc/systemd/system/dev-backup.service <<UNIT
[Unit]
Description=exit-dev repo backup to GCS
[Service]
Type=oneshot
User=${DEV_USER}
ExecStart=/usr/local/bin/dev-backup
UNIT
cat > /etc/systemd/system/dev-backup.timer <<'UNIT'
[Unit]
Description=Daily exit-dev repo backup
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now dev-idle.timer dev-backup.timer

# ── 16. Tailscale ────────────────────────────────────────────────────────────
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

# Stop/start cycle: already authenticated → refresh settings and exit.
if tailscale status &>/dev/null; then
  tailscale set --ssh --accept-dns=false
  exit 0
fi

# First boot: pull the auth key from Secret Manager via the metadata SA token.
# --accept-dns=false: keep MagicDNS out of /etc/resolv.conf so it can't clash
# with kind's in-cluster DNS or Docker's embedded resolver.
PROJECT=$(meta project/project-id)
TOKEN=$(meta instance/service-accounts/default/token \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
AUTH_KEY=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/exit-dev-tailscale-auth-key/versions/latest:access" \
  | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode().strip())")

tailscale up \
  --authkey="${AUTH_KEY}" \
  --ssh \
  --hostname="${HOSTNAME_TS}" \
  --accept-dns=false
