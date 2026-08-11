# Shell Configuration

## Architecture

The shell is bash (Homebrew's modern version, not macOS system bash).

```
~/.bash_profile          # Login shell: env vars, PATH
  └─ sources ~/.bashrc

~/.bashrc                # Interactive shell: SHARED, platform-neutral
  └─ sources ~/.bash/*.bash modules
  └─ sources exactly one of:
       ~/.bash/macos.bash   (macOS — owned by the Mac)
       ~/.bash/linux.bash   (Linux — owned by the devbox)
  └─ activates mise, cargo, deno
```

## Ownership

`~/.bashrc` is installed **verbatim on both machines**, so nothing platform-specific
belongs in it. Each platform file is owned by the machine it runs on:

| Change | Where it goes |
|---|---|
| macOS-only | `bash/macos.bash`, edited on the Mac |
| Linux-only | `bash/linux.bash`, edited on the devbox |
| Genuinely both | `bashrc` — a deliberate repo edit, not a sync |

This is enforced, not just documented. `inventory.sh` syncs `bash/*.bash` back from
the machine but **no longer syncs `bashrc`**; it reports divergence and leaves the
tracked copy authoritative. The rule exists because a routine sync once deleted 79
lines of Linux-only configuration — the Mac's copy was simply stale, and nothing
arbitrated between `restore.sh` (repo → live) and `inventory.sh` (live → repo).

Where the two platform files make opposite choices — the SSH agent socket and
`DO_NOT_TRACK` — the reasoning is written on both sides. Read them together.

## Module breakdown (`~/.bash/`)

| File | Purpose |
|---|---|
| `macos.bash` | Homebrew shellenv, macOS aliases, macOS-only exports, completion sources |
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
- **Containers**: `KIND_EXPERIMENTAL_PROVIDER=podman` — kind defaults to docker, which
  is not installed here; podman is the Mac's runtime

## Dotfiles management

This repo (`0x58/macos/dotfiles/`) is the primary dotfile backup. The `config` alias in `.bashrc` references `~/.mydot/` but that bare repo no longer exists.

## PATH order (effective)

1. mise-managed shims
2. pnpm global
3. Google Cloud SDK
4. Homebrew (`/opt/homebrew/...`)
5. `~/.local/bin`, `~/go/bin`, `~/bin`
6. System paths
