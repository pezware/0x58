---
name: Terminal keys — control bytes, modified keys, and the macOS/kitty layers
description: Why some terminal shortcuts work everywhere and others break; the reliable control bytes for Claude Code / tmux / kitty on macOS
type: reference
---

## The three-layer model — who handles a keystroke decides how reliable it is

A keystroke is intercepted by the **first** layer that claims it. The lower the layer, the more bulletproof the key:

1. **tty line discipline** (kernel terminal driver) — `Ctrl+C/D/U/W/Z`. Handled before any app sees them, so they *never* break regardless of terminal config.
2. **readline / app line editing** — `Ctrl+A/E/K`, etc. The app interpreting raw bytes. Works wherever the app uses readline-style editing (Claude Code input box, bash).
3. **modified keys** — `Shift+Enter`, `Ctrl+arrow`. These must be *encoded* by the terminal into escape sequences. This is the fragile layer — encoding depends on terminal type and OS shortcut grabs.

**Practical takeaway:** memorize layer-1 keys and you're immune to encoding problems.

## Why `Ctrl+letter` = a low byte

Holding Ctrl masks off the high bits of the letter:
- `Ctrl+J` → 0x0A (LF) — a literal **newline**. Works as "insert newline" everywhere, including the Claude Code input box.
- `Ctrl+C` → 0x03, `Ctrl+D` → 0x04.
- `Ctrl+[` → 0x1B, which **is** Escape — handy in vim/nvim when Esc is awkward.

`Enter` is 0x0D (CR), which TUIs conventionally treat as "submit" — that's why `Ctrl+J` (LF) inserts a newline while Enter sends.

## Reliable keys cheat sheet

**tty-level (universal):** `Ctrl+C` interrupt · `Ctrl+D` EOF · `Ctrl+U` kill line · `Ctrl+W` delete word · `Ctrl+L` clear · `Ctrl+J` newline · `Ctrl+Z` suspend (shell only).

**readline (Claude Code input + bash):** `Ctrl+A`/`Ctrl+E` start/end of line · `Ctrl+K` kill to end of line · `Ctrl+R` reverse history search (bash).

**Claude Code:** `Ctrl+O` toggle transcript mode.

**tmux (prefix `Ctrl+b`):** `Ctrl+b [` copy/scrollback mode · inside copy mode `Ctrl+u`/`Ctrl+d` half-page.

**Context collision to watch:** `Ctrl+U`/`Ctrl+D` mean "kill line"/"EOF" at a shell prompt but "half-page scroll" inside tmux copy-mode and vim — same bytes, different handler depending on what's reading.

## macOS Mission Control steals all four `Ctrl+arrow` keys

This is why tmux's *default* `Ctrl+arrow` pane-resize bindings appear dead on macOS — the keys are grabbed by the window server before reaching the terminal:

| Key | macOS default |
|-----|---------------|
| `Ctrl+←` / `Ctrl+→` | Move left/right a space |
| `Ctrl+↑` | Mission Control |
| `Ctrl+↓` | Application windows (App Exposé) |

**Fix options:** untick them in System Settings → Keyboard → Keyboard Shortcuts → Mission Control; OR bind alternatives that macOS doesn't grab (e.g. tmux `prefix + H/J/K/L` for resize, since `Alt+arrow` and plain letters are free).

## kitty: `term xterm-256color` masks modified-key encoding

Overriding `term` to plain `xterm-256color` in `kitty.conf` (instead of letting kitty default to `xterm-kitty`) stops kitty advertising its extended keyboard protocol. Consequence: `Shift+Enter` collapses to the same byte as plain `Enter` (`\r`), so apps can't distinguish them — Shift+Enter just submits instead of inserting a newline.

**Workarounds:**
- Use `Ctrl+J` (always works — it's a raw LF byte, no encoding needed).
- Or restore Shift+Enter with a kitty map: `map shift+enter send_text all \x1b[13;2u` (CSI-u encoding) — or simpler `send_text all \n`.
- Or remove the `term` override (fixes several modified keys at once) — but only if your other tools have matching `xterm-kitty` terminfo.

**Discovered:** 2026-06, debugging tmux pane resize + Claude Code newline input on macOS/kitty.
