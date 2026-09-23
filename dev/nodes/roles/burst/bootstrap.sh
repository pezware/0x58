#!/usr/bin/env bash
# burst role — disposable kind host for builds and tests.
#
# Holds nothing worth keeping: repos are rsync'd in from the controller and the
# box is destroyed when the session ends. It fetches no code of its own and
# carries no provider credential, which is what keeps a compromised build from
# reaching anything beyond itself.
#
# TODO(#106): the docker/kind/kubectl block below duplicates roles/k8s and, once
# #103 lands, roles/testbox as well. Extracting one `ensure_kind_cluster` helper
# is already logged as a follow-up on #103; do it there rather than here, so the
# extraction lands once against all three callers instead of racing them.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy
CLUSTER_NAME="${CLUSTER_NAME:-dev}"

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

first_boot || { log "per-boot: nothing to do"; exit 0; }

# ── Docker: kind's "nodes" are containers, which is why this works on a VPS ──
log "installing docker"
apt-get update -qq || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io || {
    log "docker install FAILED — cannot continue with kind"
    exit 0   # node stays on the tailnet for debugging
}
usermod -aG docker "$USER_NAME"
systemctl enable --now docker

# ── kind + kubectl ──────────────────────────────────────────────────────────
# Resolved at boot rather than pinned: a stale pin silently fails to download
# long after anyone remembers this file exists.
install_kind() {
    local ver
    ver=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    [ -n "$ver" ] || { log "could not resolve kind version"; return 1; }
    log "installing kind $ver"
    curl -fsSLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/$ver/kind-linux-amd64"
    chmod 0755 /usr/local/bin/kind
}

install_kubectl() {
    local ver
    ver=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    [ -n "$ver" ] || { log "could not resolve kubectl version"; return 1; }
    log "installing kubectl $ver"
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$ver/bin/linux/amd64/kubectl"
    chmod 0755 /usr/local/bin/kubectl
}

command -v kind    >/dev/null || install_kind    || log "kind install failed (non-fatal)"
command -v kubectl >/dev/null || install_kubectl || log "kubectl install failed (non-fatal)"

# ── Build toolchain ─────────────────────────────────────────────────────────
# A JDK, because the thing this box exists to build is Kotlin. Everything else
# the build needs comes in with the source tree.
log "installing build toolchain"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    default-jdk-headless git rsync || log "toolchain install partially failed (non-fatal)"

# ── kind cluster config bound to the TAILNET address ────────────────────────
# kind binds its API server to 127.0.0.1 by default, so the kubeconfig it emits
# is useless from the controller and the serving cert carries no SAN for any
# other address. Both are fixed by setting apiServerAddress BEFORE the cluster
# is created — it cannot be retrofitted.
TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
if [ -z "$TS_IP" ]; then
    log "no tailscale IPv4 yet — skipping cluster creation; rerun node-bootstrap later"
    exit 0
fi

CFG="/home/$USER_NAME/kind-cluster.yaml"
cat > "$CFG" <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  # Tailnet address of this node. The API server is reachable ONLY over the
  # tailnet — the instance firewall drops every inbound packet on the public
  # interface, so this address is the only way in.
  apiServerAddress: "$TS_IP"
  apiServerPort: 6443
nodes:
  - role: control-plane
YAML
chown "$USER_NAME:$USER_NAME" "$CFG"

# ── Create the cluster ──────────────────────────────────────────────────────
# Non-fatal: a failure here still leaves a reachable node with kind installed,
# which is debuggable. An unreachable node is not.
if as_user "kind get clusters 2>/dev/null | grep -qx '$CLUSTER_NAME'"; then
    log "cluster '$CLUSTER_NAME' already exists"
else
    log "creating kind cluster '$CLUSTER_NAME' (pulls a ~1GB node image)"
    as_user "kind create cluster --name '$CLUSTER_NAME' --config '$CFG'" \
        || log "kind create FAILED — run by hand: kind create cluster --name $CLUSTER_NAME --config $CFG"
fi

log "burst bootstrap done — rsync your tree in, then build"
