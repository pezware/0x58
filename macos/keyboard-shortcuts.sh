#!/usr/bin/env bash
set -euo pipefail

# Enable macOS Mission Control "switch Space" keyboard shortcuts.
#
# These live in com.apple.symbolichotkeys as nested dicts, which the
# auto-generated defaults-dump.sh deliberately skips (it only handles scalar
# keys). macOS also ships several of them disabled by default — notably the
# numbered "Switch to Desktop N" shortcuts — so a fresh machine has no way to
# hop between Spaces from the keyboard until this runs.
#
# We write the WHOLE hotkey entry (enabled + value/parameters), not just flip
# `enabled`, so it works even when the entry is absent on a clean install.
#
# Usage:
#   ./keyboard-shortcuts.sh              # apply
#   ./keyboard-shortcuts.sh --dry-run    # print what would be set
#
# Hotkey IDs and their (charCode keyCode modifierMask) parameters:
#   79  = Move left a space   (^←)   -> 65535 123 8650752
#   81  = Move right a space  (^→)   -> 65535 124 8650752
#   118 = Switch to Desktop 1 (^1)   -> 65535 18  262144
#   119 = Switch to Desktop 2 (^2)   -> 65535 19  262144
#   120 = Switch to Desktop 3 (^3)   -> 65535 20  262144
#
# Mask note: 8650752 = control(0x40000) | function-key flag(0x800000) that
# arrow keys carry; 262144 = control only.

PLIST="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

# id -> "charCode keyCode modifierMask"
HOTKEYS=(
    "79=65535 123 8650752"
    "81=65535 124 8650752"
    "118=65535 18 262144"
    "119=65535 19 262144"
    "120=65535 20 262144"
)

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

set_hotkey() {
    local id="$1" params="$2"
    read -r p0 p1 p2 <<<"$params"

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "  hotkey $id -> enabled=true, parameters=($p0 $p1 $p2)"
        return
    fi

    # Delete-then-Add so the entry is fully deterministic whether or not it
    # already existed (Set alone fails when the key path is absent).
    /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:$id" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy \
        -c "Add :AppleSymbolicHotKeys:$id dict" \
        -c "Add :AppleSymbolicHotKeys:$id:enabled bool true" \
        -c "Add :AppleSymbolicHotKeys:$id:value dict" \
        -c "Add :AppleSymbolicHotKeys:$id:value:type string standard" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters array" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $p0" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $p1" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters: integer $p2" \
        "$PLIST"
}

echo "==> Enabling Mission Control Space-switch shortcuts"
for entry in "${HOTKEYS[@]}"; do
    set_hotkey "${entry%%=*}" "${entry#*=}"
done

if [[ "$DRY_RUN" == 1 ]]; then
    echo "==> Dry run — nothing written"
    exit 0
fi

# Flush the prefs cache (cfprefsd may hold a stale copy of the plist) and tell
# the WindowServer to reload the hotkey table — the on-disk edit is inert
# until this runs (the macOS analog of `tmux source-file`).
killall cfprefsd 2>/dev/null || true
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

echo "==> Done. ^←/^→ switch Spaces; ^1/^2/^3 jump to Desktop 1/2/3."
