# Shell Configuration

## Architecture

The shell is bash (Homebrew's modern version, not macOS system bash).

```
~/.bash_profile          # Login shell: env vars, PATH
  └─ sources ~/.bashrc

~/.bashrc                # Interactive shell: aliases, history, modular sources
  └─ sources ~/.bash/*.bash modules
  └─ sources ~/.bash/macos.bash (macOS-only)
  └─ activates mise, cargo, deno
```

## Module breakdown (`~/.bash/`)

| File | Purpose |
|---|---|
| `macos.bash` | Homebrew shellenv, macOS aliases, completion sources |
| `prompt.bash` | Custom PS1 prompt |
| `history.bash` | History configuration |
| `go.bash` | Go environment setup |
| `glow.bash` | Glow terminal markdown rendering config |
| `kubectl-context.bash` | Kubernetes context/namespace helpers |
| `work_alias.bash` | Work-specific aliases (k8s, project shortcuts) |

## Key settings

- **History**: 10k lines, timestamped, deduped, appended (not overwritten)
- **Editor**: `nvim` (aliased as `vi`/`vim`)
- **Pager**: `bat` (aliased as `cat`), `less -r`
- **Version manager**: `mise activate bash` at end of `.bashrc`
- **GPG**: `GPG_TTY=$(tty)` for commit signing
- **Privacy**: `DO_NOT_TRACK=1`

## Dotfiles management

This repo (`0x58/macos/dotfiles/`) is the primary dotfile backup. The `config` alias in `.bashrc` references `~/.mydot/` but that bare repo no longer exists.

## PATH order (effective)

1. mise-managed shims
2. pnpm global
3. Google Cloud SDK
4. Homebrew (`/opt/homebrew/...`)
5. `~/.local/bin`, `~/go/bin`, `~/bin`
6. System paths
