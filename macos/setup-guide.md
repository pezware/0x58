# macOS Setup Guide

Minimal bootstrap for: kitty + bash + nvim + git + w3m + claude/codex + gcloud.

## Quick Start

```bash
# Clone this repo (or access from external drive at ~/src)
git clone https://github.com/pezware/0x58.git ~/src/public/0x58

# Run the restore script
./macos/restore.sh
```

The script handles: brew install, dotfile placement, dev tool setup, and macOS defaults. It prints remaining manual steps at the end.

For Linux (OrbStack VMs), the same script detects the platform and installs via apt instead.

## What the Script Does

| Phase | macOS | Linux |
|---|---|---|
| Packages | `brew bundle` from Brewfile | `apt install` core tools + mise |
| Dotfiles | bash, vim, nvim, kitty, git, w3m | bash, vim, nvim, w3m (no kitty) |
| Dev tools | vim-plug, npm globals | vim-plug, npm globals |
| Preferences | defaults-dump.sh (Dock, Finder, etc.) | skipped |

## What Requires Manual Steps

### SSH (Secretive) — macOS only
Secretive creates a new Secure Enclave key pair per machine. **Keys are non-transferable.**
1. Open Secretive app
2. Add the new public key to GitHub (Settings → SSH keys)
3. Add to remote servers: `pezware-uno`, `pezware-dos`
4. Verify: `ssh -T git@github.com`

### GPG (commit signing)
```bash
# Restore from backup (see "GPG Key Backup" below)
gpg --import ~/src/secrets/gpg-private.asc
gpg --import-ownertrust ~/src/secrets/gpg-ownertrust.txt
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

### Auth
```bash
gh auth login                      # browser-based, uses keychain
gcloud init && gcloud auth login   # browser-based
```

### macOS Settings (cannot be scripted)
- Caps Lock → Control: System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys
- Display scaling: System Settings → Displays

### Claude Code
Claude config lives at `~/src/claude` on the external drive. After restoring dotfiles (which set `CLAUDE_CONFIG_DIR`), symlink it:
```bash
ln -s ~/src/claude ~/.claude
```

### Tailscale
Client-only on macOS — just sign in.

---

## GPG Key Backup

Store GPG keys in `~/src/secrets/` on the external drive with local-only version control:

### Backup (do this now)
```bash
mkdir -p ~/src/secrets
cd ~/src/secrets
git init

# Export keys
gpg --export-secret-keys --armor > gpg-private.asc
gpg --export --armor > gpg-public.asc
gpg --export-ownertrust > gpg-ownertrust.txt

# Commit locally (never push)
git add -A
git commit -m "gpg key backup"
```

### Restore (on new machine)
```bash
gpg --import ~/src/secrets/gpg-private.asc
gpg --import-ownertrust ~/src/secrets/gpg-ownertrust.txt
gpg --list-secret-keys --keyid-format=long  # find KEY_ID
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

### Notes
- `~/src/secrets/` lives on the external drive — survives macOS reinstall
- Local git only — **never add a remote, never push**
- The private key file (`gpg-private.asc`) is the crown jewel — if you lose the drive, you lose the key

---

## Verification

- [ ] `kitty` launches with correct theme
- [ ] `nvim` opens with plugins loaded (`:Lazy`)
- [ ] `ssh -T git@github.com` succeeds
- [ ] `git commit --allow-empty -m "test"` produces signed commit
- [ ] `gcloud auth list` shows active account
- [ ] `claude` and `codex` work
- [ ] `w3m https://example.com` renders
- [ ] Caps Lock acts as Control
- [ ] `brew bundle check --file=macos/Brewfile` passes

## External Drive Assumption

The external drive mounts with partitions including `~/src`. As long as auto-mount works:
- All project data in `~/src/` is already there
- Claude config at `~/src/claude` is already there
- GPG backup at `~/src/secrets/` is already there
- Only the dotfiles and packages need to be restored (that's what `restore.sh` does)
