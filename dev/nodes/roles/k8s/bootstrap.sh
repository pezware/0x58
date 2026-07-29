#!/usr/bin/env bash
# k8s role — disposable kind host. Holds nothing worth keeping: repos live on
# the devbox, and this box is destroyed when the session ends.
#
# kind rather than k3s because the Mac workflow already uses it — kubectl-context.bash
# has kube-setup-kind, and dev/kind/ carries the cluster config and Taskfile. Same
# tool both ends means one set of habits.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy
CLUSTER_NAME="${CLUSTER_NAME:-dev}"

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

# ── Docker: kind's "nodes" are containers, which is why this works on a VPS ──
# (A VM-driver minikube would need nested virtualisation, which Linode has not.)
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

# ── kind cluster config bound to the TAILNET address ────────────────────────
# This is the step everyone misses: kind binds its API server to 127.0.0.1 by
# default, so the kubeconfig it emits is useless from the devbox, and the API
# server cert carries no SAN for any other address. Both are fixed by setting
# apiServerAddress before the cluster is created — it cannot be retrofitted.
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
  # Tailnet address of this node — lets kubectl on the devbox reach the API
  # server, and puts the address in the serving cert's SANs.
  apiServerAddress: "$TS_IP"
  apiServerPort: 6443
nodes:
  # Single node: 4 GB comfortably fits one, a 3-node cluster lands near 3 GB
  # and leaves nothing for what you are actually testing.
  - role: control-plane
YAML
chown "$USER_NAME:$USER_NAME" "$CFG"

# ── Create the cluster ──────────────────────────────────────────────────────
# This box exists solely to hold a cluster, so bring one up. Non-fatal: a
# failure here still leaves a reachable node with kind installed.
if as_user "kind get clusters 2>/dev/null | grep -qx '$CLUSTER_NAME'"; then
    log "cluster '$CLUSTER_NAME' already exists"
else
    log "creating kind cluster '$CLUSTER_NAME' (pulls a ~1GB node image)"
    as_user "kind create cluster --name '$CLUSTER_NAME' --config '$CFG'" \
        || log "kind create FAILED — run it by hand: kind create cluster --name $CLUSTER_NAME --config $CFG"
fi

log "k8s bootstrap done"
