#!/usr/bin/env bash
# Rename the tmux window holding THIS Claude Code session to "branch · topic".
#   branch — current git branch of the pane's cwd (fallback: directory name)
#   topic  — Claude Code's conversation title, captured by tmux as #{pane_title}
#
# Wired up via SessionStart / UserPromptSubmit / Stop hooks in ~/.claude/settings.json.
# Safe no-op when not inside tmux. Targets the exact pane via $TMUX_PANE, so it
# can never rename whatever window happens to be active elsewhere.
#
# Note: `tmux rename-window` turns OFF automatic-rename for this window, which is
# what makes our name stick. #{pane_title} keeps tracking Claude's OSC title
# regardless, so re-running on each prompt refreshes the topic half.
set -u
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

dir="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)"
dir="${dir:-$PWD}"

branch="$(git -C "$dir" branch --show-current 2>/dev/null)"
[ -n "$branch" ] || branch="$(basename "$dir")"

topic="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null)"
# Claude Code prefixes the title with an animated braille spinner (U+2800-U+28FF)
# while it's working; strip any leading spinner glyphs plus surrounding space.
topic="$(printf '%s' "$topic" | sed -E 's/^[[:space:]]*[⠀-⣿]+[[:space:]]*//; s/^[[:space:]]+//; s/[[:space:]]+$//')"

# Skip a topic that carries no signal: empty, a bare shell name, a path, or
# just the branch again.
case "$topic" in
  ""|bash|-bash|zsh|-zsh|/*|"$branch") name="$branch" ;;
  *) name="$branch · $topic" ;;
esac

tmux rename-window -t "$TMUX_PANE" "$name"
