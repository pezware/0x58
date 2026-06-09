---
name: Bash sourced script gotchas
description: Pitfalls when writing bash scripts that are source'd into interactive shells
type: reference
---

## `cat` aliased to `bat` breaks heredocs in sourced scripts

When a script is `source`d (not executed as a subprocess), it inherits the interactive
shell's aliases. If `alias cat=bat` is defined before the script is sourced, any
`cat > file <<HEREDOC` in the script will call `bat` instead.

**Symptom:** Files created by heredoc are 0 bytes. If `bat` isn't in PATH yet during
early shell init, you get `bash: bat: command not found` and the `>` redirection has
already truncated the file.

**Fix:** Use `command cat` to bypass aliases and functions:
```bash
command cat > "$file" <<EOF
content here
EOF
```

**Why:** Shell redirection (`>`) truncates the target file *before* the command runs.
If the command then fails (bat not found) or produces different output (bat decorations),
the file ends up empty or corrupted.

**General rule:** In sourced scripts, use `command <cmd>` for any builtin/common command
that users commonly alias (`cat`, `ls`, `grep`, `rm`, etc.).

**Discovered:** 2026-04-09, debugging per-window kubeconfig overlay in `~/.bash/kubectl-context.bash`.
