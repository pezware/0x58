#!/usr/bin/env bash
set -euo pipefail

# Silences the background agents of stock Apple apps this user never opens.
#
# WHY THIS DOES NOT DELETE THE APPS
#
# It cannot. Every app it targets lives in /System/Applications, on the sealed
# signed system volume. Three locks stack there, measured on macOS 26.6.1:
#
#   /dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
#   System Integrity Protection status: enabled.
#   Authenticated Root status: enabled
#
# The seal covers the whole volume tree, not one file, so a deletion invalidates
# the boot snapshot rather than freeing a bundle. Breaking it (csrutil disable +
# csrutil authenticated-root disable, from recovery) turns off Apple Intelligence,
# Apple Pay and iPhone Mirroring, and every OS update reverts it. It also reclaims
# almost nothing: the entire system volume holds 12Gi against 148Gi of user data.
#
# The cost of an unused Apple app is not disk. It is the launchd agent that runs
# whether or not you open the app. This script disables those agents.
#
# `launchctl disable` writes to /var/db/com.apple.xpc.launchd/disabled.<uid>.plist
# in the USER domain, so no sudo, and the veto survives reboots.
#
# IT TAKES EFFECT AT THE NEXT LOGIN, not immediately. SIP refuses to let even the
# owning user boot out or signal an Apple agent (rc 150), so the copies running
# now outlive the script. See bootout_service() for the measured errors.
#
# Usage:
#   ./disable-system-apps.sh              # Disable both sets (default)
#   ./disable-system-apps.sh --safe-only  # Skip the set that breaks features
#   ./disable-system-apps.sh --dry-run    # Print the commands, change nothing
#   ./disable-system-apps.sh --status     # Report the current state of each label
#   ./disable-system-apps.sh --undo       # Restore what THIS script disabled

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/0x58"
JOURNAL="$STATE_DIR/disabled-system-apps.journal"

# TWO DOMAINS, AND THEY ARE NOT INTERCHANGEABLE.
#
# The disable override is one plist keyed by UID
# (/var/db/com.apple.xpc.launchd/disabled.501.plist), so `disable` and `enable`
# reach both domains through either name, and print-disabled reports the same
# list from either. Verified: user/501 and gui/501 return identical output.
#
# `bootout` does NOT work that way. It needs the domain the service is actually
# bootstrapped in, and these Aqua-session agents live in gui/$UID. Aiming it at
# user/$UID returns rc 3 "No such process" — the same code a service that is
# already idle returns, so the failure is indistinguishable from success unless
# you check the PID afterwards. Measured: a first run reported all 29 labels
# "disabled" while every original PID stayed alive (imagent 687, homed 97935).
DISABLE_DOMAIN="user/$(id -u)"
BOOTOUT_DOMAIN="gui/$(id -u)"

# --- Agent lists -------------------------------------------------------------
#
# Grouped by app so a whole app can be commented out in one block. Every label
# below was confirmed present by `launchctl list` on macOS 26.6.1 (build 25G76).
#
# Stocks, Journal and Dictionary carry NO background agent — they are inert
# bundles that cost nothing while closed. Do not go looking for their labels.

AGENTS_SAFE=(
    com.apple.newsd                             # News
    com.apple.weatherd                          # Weather
    com.apple.podcasts.PodcastContentService    # Podcasts
    com.apple.videosubscriptionsd               # TV
    com.apple.bookassetd                        # Books
    com.apple.bookdatastored                    # Books
    com.apple.homed                             # Home
    com.apple.Maps.mapspushd                    # Maps
    com.apple.Maps.mapssyncd                    # Maps
    com.apple.maps.destinationd                 # Maps
    com.apple.gamed                             # Games
    com.apple.gamesaved                         # Games
    com.apple.GamePolicyAgent                   # Games
    com.apple.GameOverlayUI                     # Games
    com.apple.gamecontroller.ConfigService      # Games
    com.apple.AMPDeviceDiscoveryAgent           # Music
    com.apple.AMPLibraryAgent                   # Music
    com.apple.AMPArtworkAgent                   # Music
    com.apple.AMPDevicesAgent                   # Music
    com.apple.AMPSystemPlayerAgent              # Music
    com.apple.amp.mediasharingd                 # Music
    com.apple.photoanalysisd                    # Photos: face/scene indexing only
    com.apple.generativeexperiencesd            # Image Playground / Apple Intelligence
)

# These END a feature rather than idling a daemon. Named separately so the
# hazard survives in the file, not only in the commit message.
#
#   imagent, facetimemessagestored  -> no iMessage, no FaceTime, no iPhone SMS relay
#   email.maild and friends         -> no Mail; Calendar invitations route through it
#   photolibraryd                   -> the system photo picker fails in OTHER apps
#
# NOT included: com.apple.GameController.gamecontrolleragentd. It serves physical
# game controllers system-wide, not the Games app, so disabling it would break a
# gamepad in every app that reads one.
AGENTS_BREAKING=(
    com.apple.imagent                           # Messages
    com.apple.facetimemessagestored             # Messages
    com.apple.email.maild                       # Mail
    com.apple.MailServiceAgent                  # Mail
    com.apple.icloudmailagent                   # Mail
    com.apple.photolibraryd                     # Photos
)

# --- Helpers -----------------------------------------------------------------

DISABLED_SNAPSHOT=""

# Caches `launchctl print-disabled` once. Re-reading it per label costs a
# subprocess each time and can race with our own writes mid-run.
snapshot_disabled() {
    [[ -n "$DISABLED_SNAPSHOT" ]] && rm -f "$DISABLED_SNAPSHOT"
    DISABLED_SNAPSHOT="$(mktemp -t disabled-system-apps)"
    launchctl print-disabled "$DISABLE_DOMAIN" > "$DISABLED_SNAPSHOT" 2>/dev/null || true
    # shellcheck disable=SC2064  # expand $DISABLED_SNAPSHOT now, not at trap time
    trap "rm -f '$DISABLED_SNAPSHOT'" EXIT
}

# Prints "disabled" or "enabled" for a label.
#
# A label ABSENT from print-disabled is enabled: launchd lists only labels
# carrying an explicit override. Treating absent as "unknown" would make undo
# refuse to restore anything on a clean machine.
prior_state() {
    local label="$1" line
    line="$(grep -F "\"$label\" =>" "$DISABLED_SNAPSHOT" 2>/dev/null || true)"
    case "$line" in
        *"=> disabled"*|*"=> true"*) echo "disabled" ;;
        *)                           echo "enabled"  ;;
    esac
}

# Reports whether launchd knows this label at all.
#
# CAUTION: `launchctl list <label>` returns rc 113 for a DISABLED label and rc
# 113 for a label that does not exist. Measured on 26.6.1: com.apple.Siri.agent
# (disabled here) and com.apple.bogus.nope both give 113. So this answer is only
# trustworthy for a label prior_state() already reported as "enabled". Every
# caller checks prior_state first — reversing that order makes a second run
# report every label it just disabled as missing.
label_exists() {
    launchctl list "$1" >/dev/null 2>&1
}

# Tries to kill the RUNNING copy, and reports the outcome honestly.
#
# WITH SIP ON, THIS ALWAYS FAILS, AND THAT IS FINE.
#
#   $ launchctl bootout gui/501/com.apple.homed
#   Boot-out failed: 150: Operation not permitted while System Integrity
#   Protection is engaged
#   $ launchctl kill SIGTERM gui/501/com.apple.homed
#   Not privileged to signal service.
#
# SIP shields Apple's own agents from being booted out or signalled, even by the
# user who owns them. So the `disable` override is the part that does the work:
# launchd honours it at the NEXT login and never starts the agent again. The
# processes running right now simply outlive this script.
#
# Prints a suffix for the caller's line rather than returning a code, because
# every outcome here is worth seeing rather than swallowing.
bootout_service() {
    local label="$1" rc=0
    launchctl bootout "$BOOTOUT_DOMAIN/$label" 2>/dev/null || rc=$?
    case "$rc" in
        0)   echo " (killed running copy)" ;;
        150) echo " (running until logout: SIP)" ;;
        3)   echo " (was already idle)" ;;
        *)   echo " (bootout rc=$rc; ends at next login)" ;;
    esac
}

# TODO(you): decide the policy when a label is missing — see the note this
# script printed. Apple renames agents between releases, so a list correct on
# macOS 26 will drift on 27. Current behaviour: warn and continue.
handle_missing_label() {
    local label="$1"
    echo "    WARN: $label not found in $DISABLE_DOMAIN — skipped" >&2
}

# --- Modes -------------------------------------------------------------------

do_status() {
    snapshot_disabled
    local label
    for label in "${AGENTS_SAFE[@]}" "${AGENTS_BREAKING[@]}"; do
        if [[ "$(prior_state "$label")" == "disabled" ]]; then
            printf '  %-10s %s\n' "disabled" "$label"
        elif label_exists "$label"; then
            printf '  %-10s %s\n' "enabled" "$label"
        else
            printf '  %-10s %s\n' "absent" "$label"
        fi
    done
}

do_apply() {
    local dry_run="$1"; shift
    local -a targets=("$@")
    local label state

    snapshot_disabled
    mkdir -p "$STATE_DIR"

    for label in "${targets[@]}"; do
        # prior_state FIRST — see the caution on label_exists().
        state="$(prior_state "$label")"
        if [[ "$state" == "disabled" ]]; then
            echo "    skip (already disabled): $label"
            continue
        fi

        if ! label_exists "$label"; then
            handle_missing_label "$label"
            continue
        fi

        if [[ "$dry_run" == "yes" ]]; then
            echo "    launchctl disable $DISABLE_DOMAIN/$label"
            echo "    launchctl bootout  $BOOTOUT_DOMAIN/$label"
            continue
        fi

        # Journal BEFORE the change. A crash between the two leaves a
        # recoverable record; the reverse order leaves an orphaned agent.
        printf '%s\t%s\n' "$label" "$state" >> "$JOURNAL"

        launchctl disable "$DISABLE_DOMAIN/$label"
        echo "    disabled: $label$(bootout_service "$label")"
    done
}

do_undo() {
    if [[ ! -f "$JOURNAL" ]]; then
        echo "ERROR: no journal at $JOURNAL — nothing to undo" >&2
        exit 1
    fi

    # Restore only what this script changed, and only where it recorded the
    # label as previously enabled. A blanket `launchctl enable` over the lists
    # would re-enable agents something ELSE disabled — this machine already
    # carries com.apple.Siri.agent and com.apple.iCloudHelper disabled by hand.
    local label state
    while IFS=$'\t' read -r label state; do
        [[ -n "$label" ]] || continue
        if [[ "$state" != "enabled" ]]; then
            echo "    left disabled (was disabled before): $label"
            continue
        fi
        launchctl enable "$DISABLE_DOMAIN/$label"
        echo "    enabled: $label"
    done < "$JOURNAL"

    mv "$JOURNAL" "$JOURNAL.$(date -u +%Y%m%dT%H%M%SZ).undone"
    echo "==> Log out and back in to restart the agents"
}

# --- Main --------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: macOS only" >&2; exit 1; }

MODE="apply"
DRY_RUN="no"
INCLUDE_BREAKING="yes"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --undo)      MODE="undo" ;;
        --status)    MODE="status" ;;
        --dry-run)   DRY_RUN="yes" ;;
        --safe-only) INCLUDE_BREAKING="no" ;;
        -h|--help)   sed -n '4,36p' "$0"; exit 0 ;;
        *)           echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

case "$MODE" in
    status)
        echo "==> Agent state in $DISABLE_DOMAIN"
        do_status
        ;;
    undo)
        echo "==> Restoring agents recorded in $JOURNAL"
        do_undo
        ;;
    apply)
        echo "==> Disabling stock-app agents in $DISABLE_DOMAIN (dry-run: $DRY_RUN)"
        echo "  -- safe set"
        do_apply "$DRY_RUN" "${AGENTS_SAFE[@]}"
        if [[ "$INCLUDE_BREAKING" == "yes" ]]; then
            echo "  -- breaking set: ends iMessage, FaceTime, SMS relay, Mail, photo picker"
            do_apply "$DRY_RUN" "${AGENTS_BREAKING[@]}"
        else
            echo "  -- breaking set skipped (--safe-only)"
        fi
        if [[ "$DRY_RUN" == "no" ]]; then
            echo "==> Log out and back in — SIP keeps the running agents alive until then"
            echo "==> Undo with: $0 --undo"
        fi
        ;;
esac
