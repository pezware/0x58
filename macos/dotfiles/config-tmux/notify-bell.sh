#!/usr/bin/env bash
# Post a macOS Notification Center banner when a tmux window rings the bell.
#
# Wired up via the `alert-bell` hook in tmux.conf, which passes the BELLING
# window's session name + index (both safe tokens — no spaces). We look the
# window NAME up ourselves so a title with spaces/emoji (claude/codex set fancy
# OSC titles) can't break argument parsing or inject into the AppleScript.
#
# Tool-agnostic by design: claude AND codex both ring the terminal bell, so this
# one hook covers both — and any other program that emits BEL. A Notification
# Center banner is the only alert that crosses fullscreen Spaces (kitty's Dock
# bounce is invisible when the Dock is hidden in fullscreen).
#
# Always exits 0; never blocks (osascript returns immediately, unlike
# terminal-notifier which can hang without a GUI bootstrap context).
set -u

sess="${1:-?}"
win="${2:-?}"

# Look up the window name from the belling target. Falls back to the index.
wname=""
if command -v tmux >/dev/null 2>&1; then
  wname="$(tmux display-message -p -t "${sess}:${win}" '#{window_name}' 2>/dev/null || true)"
fi
wname="${wname:-window $win}"

# Values passed as AppleScript argv (after the script), never interpolated into
# the source — so quotes/backslashes in a window name can't break or inject.
/usr/bin/osascript \
  -e 'on run {theSession, theWindow}' \
  -e 'display notification theWindow with title "tmux bell" subtitle theSession' \
  -e 'end run' \
  "$sess" "$wname" >/dev/null 2>&1 || true

exit 0
