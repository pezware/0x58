#!/usr/bin/env bash
# minimal role — exit node and nothing else. The tier you scale back to when
# devbox and k8s are destroyed and you just want the tailnet to keep working.
#
# Functionally equivalent to dev/exit-node/linode/bootstrap.sh; that one stays
# put because it owns live state for the running pezware-cuatro.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

# IPv6 fully disabled, matching the existing exit node — this tailnet does not
# use it, and leaving it on means a second address family to reason about when
# exit-node routing misbehaves.
cat > /etc/sysctl.d/99-no-ipv6.conf <<'SYSCTL'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-no-ipv6.conf >/dev/null

log "minimal bootstrap done — advertising as exit node"
