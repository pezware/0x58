#!/usr/bin/env bash
# devbox role — the always-on workspace: repos, Claude Code / Codex in tmux,
# kubectl pointed at whatever k8s node happens to exist.
#
# Ordering matters: common_main joins the tailnet FIRST, so if the heavy
# provisioning below fails you can still SSH in and fix it by hand. Everything
# after the join is therefore non-fatal by design.
set -euo pipefail

# shellcheck source=/dev/null
. /usr/local/sbin/node-common.sh
common_main

USER_NAME=arbeitandy
REPO_REF="${REPO_REF:-main}"

as_user() { sudo -u "$USER_NAME" -H bash -lc "$*"; }

if first_boot; then
    # ── mosh: survives the wifi-to-cellular handover that kills plain ssh ────
    log "installing mosh"
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mosh || log "mosh install failed (non-fatal)"

    # ── Hand off to the repo's own bootstrap ────────────────────────────────
    # Deliberately the SAME entry point a human would use, so there is one code
    # path to keep working rather than a divergent cloud-init copy.
    log "running 0x58 start.sh (ref: $REPO_REF)"
    if as_user "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/pezware/0x58/$REPO_REF/linux/start.sh)\""; then
        log "0x58 restore complete"
    else
        log "0x58 restore FAILED — node is on the tailnet, finish it manually (see post_apply_steps)"
    fi
fi

# ── A tmux session waiting to be attached (EVERY boot) ──────────────────────
# So `mosh devbox -- tmux attach -t main` works on the first connection from a
# phone rather than erroring with "no server running" — and, because tmux dies
# with the machine, so it still works after a reboot. This is the specific thing
# that made a per-boot unit necessary rather than relying on cloud-init.
if ! as_user 'tmux has-session -t main 2>/dev/null'; then
    log "creating detached tmux session 'main'"
    as_user 'tmux new-session -d -s main' || log "tmux session create failed (non-fatal)"
fi

log "devbox bootstrap done"
