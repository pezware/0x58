#!/usr/bin/env bash
#
# Devbox backup — runs ON THE MAC, pulls FROM the devbox.
#
#   ./backup-devbox.sh status              what would be lost right now
#   ./backup-devbox.sh snapshot            timestamped pull (the daily driver)
#   ./backup-devbox.sh list                show snapshots and sizes
#   ./backup-devbox.sh restore <snap> <dst>  copy a snapshot back out
#
# Direction is the whole security design: the Mac connects outward to the
# devbox, so the devbox needs no key, token, or tailnet permission that can
# reach the laptop. The ACL deliberately blocks devbox -> Mac; a push-based
# backup would require punching a hole in exactly the rule protecting the Mac.
#
# Snapshots are hardlinked against the previous one (--link-dest), so unchanged
# files cost no additional disk. Thirty daily snapshots of a 10 GB tree occupy
# roughly 10 GB plus the churn, not 300 GB.
set -euo pipefail

HOST="${DEVBOX_HOST:-pezware-devbox}"
REMOTE_USER="${DEVBOX_USER:-arbeitandy}"
DEST_ROOT="${DEVBOX_BACKUP_DIR:-$HOME/backups/devbox}"
REMOTE_SRC="${DEVBOX_SRC:-/home/arbeitandy/src/}"

# NEVER pull these. A backup that quietly accumulates OAuth tokens turns every
# snapshot into a second copy of the credentials the threat model says should
# exist in exactly one revocable place.
readonly SECRET_EXCLUDES=(
    --exclude '.claude/.credentials.json'
    --exclude '.codex/auth.json'
    --exclude '.ssh/'
    --exclude '.config/gcloud/'
    --exclude '.npmrc'
    --exclude '**/*.pem'
    --exclude '**/*.key'
    --exclude '**/terraform.tfstate*'
    --exclude '**/.env'
)

# Reproducible from lockfiles or provisioning. Measured on the real tree:
# node_modules + .terraform alone are ~29 GB of a 50 GB source directory.
readonly JUNK_EXCLUDES=(
    --exclude 'node_modules/'
    --exclude '.terraform/'
    --exclude '.next/'
    --exclude '.venv/'
    --exclude '__pycache__/'
    --exclude 'target/'
    --exclude '.gradle/'
    --exclude '.cache/'
    # Every ext4 filesystem has one, root-owned 0700, so rsync running as a
    # normal user cannot read it and exits 23. It holds nothing worth keeping —
    # only orphaned inodes fsck recovers, which are not backup material.
    --exclude 'lost+found/'
)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

remote() { ssh -o ConnectTimeout=20 "${REMOTE_USER}@${HOST}" "$@"; }

require_host() {
    remote true 2>/dev/null || die "cannot reach ${REMOTE_USER}@${HOST} (tailnet up? node running?)"
}

# ── status: what is not yet safe anywhere else ──────────────────────────────
# Committed-and-pushed work is already protected by Git remotes. This reports
# only the classes a snapshot is actually responsible for.
cmd_status() {
    require_host
    echo "==> Repos with uncommitted or unpushed work on ${HOST}"
    remote "bash -s" <<'REMOTE'
shopt -s nullglob
found=0
while IFS= read -r gitdir; do
    repo=$(dirname "$gitdir")
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    unpushed=$(git -C "$repo" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty" != "0" ] || [ "$unpushed" != "0" ]; then
        printf '  %-52s dirty:%-5s unpushed:%s\n' "${repo#/home/arbeitandy/}" "$dirty" "$unpushed"
        found=1
    fi
done < <(find /home/arbeitandy/src -maxdepth 4 -type d -name .git 2>/dev/null)
[ "$found" = "0" ] && echo "  (none — everything is committed and pushed)"
REMOTE
}

# ── snapshot ────────────────────────────────────────────────────────────────
cmd_snapshot() {
    require_host
    mkdir -p "$DEST_ROOT"
    local stamp dest link_dest=()
    stamp=$(date +%Y-%m-%dT%H%M%S)
    dest="$DEST_ROOT/$stamp"

    local previous
    previous=$(find "$DEST_ROOT" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
    [ -n "$previous" ] && link_dest=(--link-dest="$previous")

    echo "==> Pulling ${HOST}:${REMOTE_SRC} -> $dest"
    [ -n "$previous" ] && echo "    hardlinking unchanged files against $(basename "$previous")"

    local rc=0
    rsync -a --delete --partial --human-readable --stats \
        "${link_dest[@]}" "${SECRET_EXCLUDES[@]}" "${JUNK_EXCLUDES[@]}" \
        "${REMOTE_USER}@${HOST}:${REMOTE_SRC}" "$dest/" || rc=$?

    # 24 is "partial transfer due to vanished source files" — normal on a live
    # box where a build deletes a temp file mid-sync, and not a reason to
    # distrust the snapshot. Anything else is real: leave the marker unwritten so
    # `list` shows INCOMPLETE, and fail loudly rather than banking a bad backup.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ]; then
        die "rsync exited $rc — snapshot left INCOMPLETE at $dest"
    fi
    if [ "$rc" -eq 24 ]; then
        echo "    note: some files vanished mid-transfer (rsync 24) — expected on a live box"
    fi

    # A snapshot nobody can date is a snapshot nobody trusts.
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$dest/.snapshot-completed"
    echo "==> Done: $dest"
    echo "    Verify a restore before relying on this. See: $0 restore"
}

cmd_list() {
    [ -d "$DEST_ROOT" ] || die "no snapshots under $DEST_ROOT"
    echo "==> Snapshots in $DEST_ROOT"
    local d
    for d in "$DEST_ROOT"/*/; do
        [ -d "$d" ] || continue
        printf '  %-24s %-8s %s\n' \
            "$(basename "$d")" \
            "$(du -sh "$d" 2>/dev/null | cut -f1)" \
            "$( [ -f "$d/.snapshot-completed" ] && echo "complete" || echo "INCOMPLETE" )"
    done
    echo
    echo "Sizes are apparent, not incremental — hardlinked files are counted in every"
    echo "snapshot that references them. 'du -sh $DEST_ROOT' gives the real total."
}

# ── restore ─────────────────────────────────────────────────────────────────
# Deliberately restores to a NEW directory rather than over anything. Restoring
# on top of a live tree is how a backup turns into an outage.
cmd_restore() {
    local snap="${1:-}" dst="${2:-}"
    [ -n "$snap" ] && [ -n "$dst" ] || die "usage: $0 restore <snapshot-name> <destination-dir>"
    local src="$DEST_ROOT/$snap"
    [ -d "$src" ] || die "no such snapshot: $src"
    [ -e "$dst" ] && die "$dst already exists — restore into a fresh path"
    [ -f "$src/.snapshot-completed" ] || echo "WARNING: $snap has no completion marker (interrupted pull?)"

    echo "==> Restoring $snap -> $dst"
    mkdir -p "$dst"
    rsync -a "$src/" "$dst/"
    echo "==> Restored $(du -sh "$dst" | cut -f1) to $dst"
}

case "${1:-snapshot}" in
    status)   cmd_status ;;
    snapshot) cmd_snapshot ;;
    list)     cmd_list ;;
    restore)  shift; cmd_restore "$@" ;;
    *)        sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
