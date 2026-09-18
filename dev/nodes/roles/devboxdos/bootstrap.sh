#!/usr/bin/env bash
# devboxdos role — tailnet exit node and second Terraform controller.
#
# Deliberately NOT a devbox. It drives; it does not work. No agents, no
# containers, no builds: 1 vCPU / 2 GB cannot host them, and a burst box can.
# Anything installed here should be justified by "a controller needs it".
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

first_boot || { log "per-boot: nothing to do"; exit 0; }

# ── Exit-node forwarding ────────────────────────────────────────────────────
# common.sh enables IPv4 forwarding for the exit-node path. IPv6 forwarding is
# NOT enabled there, so v6 traffic is not carried even though the instance has a
# v6 address. Enabled here rather than in common.sh so the Linode roles keep the
# behaviour they were tested with.
log "enabling ipv6 forwarding for exit-node duty"
printf 'net.ipv6.conf.all.forwarding = 1\n' > /etc/sysctl.d/99-0x58-v6forward.conf
sysctl -p /etc/sysctl.d/99-0x58-v6forward.conf >/dev/null 2>&1 || log "sysctl v6 forward failed (non-fatal)"

# ── Controller tooling ──────────────────────────────────────────────────────
log "installing controller tooling"
apt-get update -qq || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git curl jq unzip ca-certificates || log "apt install partially failed (non-fatal)"

# Terraform, resolved at boot rather than pinned. A stale pin fails to download
# long after anyone remembers this file exists -- the same reasoning roles/k8s
# gives for kind and kubectl.
install_terraform() {
    local ver arch
    arch=$(dpkg --print-architecture)   # amd64 | arm64
    ver=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform \
        | grep -o '"current_version":"[^"]*"' | cut -d'"' -f4)
    [ -n "$ver" ] || { log "could not resolve terraform version"; return 1; }
    log "installing terraform $ver ($arch)"
    curl -fsSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/$ver/terraform_${ver}_linux_${arch}.zip"
    unzip -o -q /tmp/tf.zip -d /usr/local/bin terraform
    chmod 0755 /usr/local/bin/terraform
    rm -f /tmp/tf.zip
}

command -v terraform >/dev/null || install_terraform || log "terraform install failed (non-fatal)"

# ── The credential file this box drives with ────────────────────────────────
# Created empty and locked down NOW so the key has somewhere safe to land. It is
# filled in by hand over Tailscale SSH -- see post_apply_steps in main.tf.
#
# Never delivered through user_data: that reaches tfstate and cloud-init's
# cache, and this state is shared between two controllers.
install -d -m 0700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.config/0x58"
install -m 0600 -o "$USER_NAME" -g "$USER_NAME" /dev/null "/home/$USER_NAME/.config/0x58/credentials.env"

# Sourced by ts-node. Absent VULTR_API_KEY, terraform fails with an auth error
# rather than anything that names the real cause, so say so up front.
cat >> "/home/$USER_NAME/.bashrc" <<'RC'

# 0x58: provider credentials for ts-node. Populated by hand over Tailscale SSH;
# see roles/devboxdos post_apply_steps. Empty until then, which makes every
# terraform call fail on auth rather than on anything that names the cause.
if [ -r "$HOME/.config/0x58/credentials.env" ]; then
    set -a; . "$HOME/.config/0x58/credentials.env"; set +a
fi
RC

log "devboxdos bootstrap done — credentials.env is EMPTY until you fill it"
