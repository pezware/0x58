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
3. Add the same public key to GitLab (Settings → SSH Keys)
4. Add to remote servers: `pezware-uno`, `pezware-dos`
5. Verify: `ssh -T git@github.com` and `ssh -T git@gitlab.com`

### Commit Signing (SSH via Secretive)
Commit signing uses the same Secretive SSH key — no GPG needed for git.
After Secretive creates your key:
```bash
# Get your Secretive public key
ssh-add -L
# Configure git to sign with it
git config --global gpg.format ssh
git config --global user.signingkey "key::$(ssh-add -L)"
git config --global commit.gpgsign true
# Set up local signature verification
echo "$(git config user.email) $(ssh-add -L)" > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```
Then add the same public key to GitHub → Settings → SSH and GPG keys → **New SSH key** → Key type: **Signing Key**.

### GPG (encryption, not needed for commit signing)
GPG private keys live in macOS Keychain (entry `gpg-archive-b64`), not on disk. Three shell functions in `~/.bash/gpg-keychain.bash` manage the lifecycle:
```bash
gpg_restore_from_keychain    # restore ~/.gnupg/ from keychain (prompts before clobbering)
gpg_verify_keychain_backup   # SHA-256 round-trip check
gpg_backup_to_keychain       # re-snapshot after generating/rotating keys
```
On the same physical Mac the keychain entry is already there. **On a different Mac** see the [Fresh machine GPG recovery](#fresh-machine-gpg-recovery) section below.

### Auth
All CLI auth lands in macOS Keychain when you log in:
```bash
gh auth login                                        # token → keychain (gh.com:oauth_token)
glab auth login --hostname gitlab.com --use-keyring  # token → keychain (no disk write)
claude auth login     # OAuth bundle → keychain (Claude Code-credentials-*)
codex login           # OAuth bundle → keychain (Codex Auth)
                      # — requires cli_auth_credentials_store = "auto" in ~/.codex/config.toml,
                      #   which is restored by restore.sh
```
gcloud has no keychain support — use the session helpers in `~/.bash/gcloud-session.bash`:
```bash
gcloud init           # one-time: pick default project
gcloud_login          # start a work session (browser-based, also updates ADC)
gcloud_status         # show active account + credentials.db state
gcloud_logout         # revoke + remove credentials.db, access_tokens.db, ADC
```
Daily habit: `gcloud_login` when you start, `gcloud_logout` when you stop.

### Kubernetes
GKE/EKS configs are restored from the repo (exec-based, no embedded credentials). Local clusters need to be recreated:
```bash
kube-setup-orbstack         # imports OrbStack k8s context (after OrbStack is running)
kube-setup-kind iden2-dev   # only if you have a kind cluster
kube-refresh                # rebuilds the merged KUBECONFIG
```
GKE/EKS auth flows through `gcloud_login` / `aws sso login`; tokens are short-lived and never persisted in kubeconfig.

### macOS Settings (cannot be scripted)
- Caps Lock → Control: System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys
- Display scaling: System Settings → Displays

### Touch ID for sudo in tmux (pam-reattach)
`restore.sh` handles this automatically on macOS (function `setup_pam_touchid`): if `pam-reattach` is installed and the wiring isn't already present in `/etc/pam.d/sudo` or `/etc/pam.d/sudo_local`, it writes the recipe into `sudo_local` (which the system `sudo` PAM stack `include`s on line 4 and which survives macOS major-version upgrades). You'll see a sudo prompt mid-bootstrap.

Symptom if missing: Touch ID works for `sudo` in a fresh terminal but silently falls back to password **inside tmux** — sudo gets reparented away from the GUI session, so `pam_tid.so` can't reach the Touch ID prompt.

Manual recipe (if you ever need to apply it by hand):
```
# /etc/pam.d/sudo_local
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
```

### Claude Code
The real Claude config directory is `~/src/claude` on the external drive; `~/.claude` is just a symlink pointing to it (`~/.claude → ~/src/claude`). The symlink is the only indirection — `CLAUDE_CONFIG_DIR` is not set. Link only when `~/.claude` is absent, so you never link onto an existing symlink (nested link) or turn `~/src/claude` itself into a symlink (loop):
```bash
[ -e ~/.claude ] || [ -L ~/.claude ] || ln -s ~/src/claude ~/.claude
```

### GitLab Mirror
This repo mirrors to GitLab. After cloning on a new machine, add the GitLab remote and push URL:
```bash
git remote add gitlab git@gitlab.com:pezware/0x58.git
git remote set-url --add --push origin git@github.com:pezware/0x58.git
git remote set-url --add --push origin git@gitlab.com:pezware/0x58.git
```
Feature branches push to both remotes automatically via `git push`. After a PR merges on GitHub, sync main manually:
```bash
git fetch origin && git push gitlab main
```

### Tailscale
Client-only on macOS — just sign in.

---

## GPG Key Backup (macOS Keychain)

GPG private keys are kept off-disk via two macOS Keychain entries:

| Service name | Holds | Size |
|---|---|---|
| `gpg-archive-b64` | base64 of `tar -czf ~/.gnupg/` (privates + pubring + trustdb + revocs) | ~96 KB |
| `keybase-paper-key-b64` | base64 of `~/.keybase-paper-key.gpg` (encrypted with iden2 key) | ~333 B |

Each entry's `-j` (kind) field embeds the decoded SHA-256 of its payload, so the restore recipe is self-describing inside the keychain.

### Snapshot (after generating or rotating keys)
```bash
gpg_backup_to_keychain         # re-snapshots ~/.gnupg/ + .keybase-paper-key.gpg
gpg_verify_keychain_backup     # SHA-256 round-trip check
```

### Same-machine restore (after accidental delete of ~/.gnupg/private-keys-v1.d/)
```bash
gpg_restore_from_keychain      # prompts before clobbering existing ~/.gnupg/
gpg --list-secret-keys         # sanity check; should show your 3 keys
```

### Fresh-machine GPG recovery

The keychain entry only exists on the original Mac. Choices for moving it:

**Option 1 — macOS Migration Assistant (recommended).** Transferring "User Accounts" copies the login keychain. After Migration Assistant completes, `gpg_restore_from_keychain` works directly on the new machine.

**Option 2 — Manual export from old machine, import on new machine.** On the old Mac:
```bash
security find-generic-password -s gpg-archive-b64 -a "$USER" -w \
  | base64 -d > /Volumes/encrypted-stick/gpg-archive.tar.gz
```
Move the tar.gz over an encrypted channel (not in-line in chat or unencrypted email). On the new Mac:
```bash
[ -d ~/.gnupg ] && mv ~/.gnupg ~/.gnupg.preexisting.$(date +%s)
tar xzf /Volumes/encrypted-stick/gpg-archive.tar.gz -C ~
chmod 700 ~/.gnupg
gpg --list-secret-keys                    # sanity check
gpg_backup_to_keychain                    # re-stage in new machine's keychain
```

**Option 3 — Truly cold backup.** If both Macs are gone, the keychain backup is gone with them. For genuine disaster recovery, also keep an offline copy:
- print the armored secret key (passphrase-protected) on paper, OR
- store a passphrase-encrypted `gpg-archive.tar.gz.gpg` in 1Password / Bitwarden / a hardware-encrypted USB key.

### Notes
- macOS Keychain at-rest encryption is bound to your login password (FileVault adds a second layer when the machine is powered off).
- The local `keymaster` CLI (`~/.local/bin/keymaster`) was evaluated for this and is unsuitable: it has a 128-byte stdin cap that silently truncates blobs. Use `security add-generic-password` directly for files >128 B. Reserve `keymaster` for short tokens where TouchID-per-access matters.

---

## Verification

- [ ] `kitty` launches with correct theme
- [ ] `nvim` opens with plugins loaded (`:Lazy`)
- [ ] `ssh -T git@github.com` succeeds
- [ ] `ssh -T git@gitlab.com` succeeds (add Secretive public key to GitLab → Settings → SSH Keys first)
- [ ] `glab auth status` shows logged in (`glab auth login --hostname gitlab.com --use-keyring`)
- [ ] `git commit --allow-empty -m "test"` produces signed commit (Touch ID prompt)
- [ ] `git log --show-signature -1` shows `Good "git" signature`
- [ ] `gpg_verify_keychain_backup gpg-archive-b64` shows `OK`
- [ ] `gpg --list-keys` shows your 3 keys (after `gpg_restore_from_keychain` if needed)
- [ ] `gh auth status` shows logged in
- [ ] `claude auth status` shows logged in (`apiProvider: firstParty`)
- [ ] `codex --version` runs (auth is keychain-backed; no `~/.codex/auth.json`)
- [ ] `gcloud_status` shows active account after `gcloud_login`
- [ ] `kubectl config current-context` resolves (orbstack by default after `kube-setup-orbstack`)
- [ ] `claude` and `codex` work
- [ ] `w3m https://example.com` renders
- [ ] Caps Lock acts as Control
- [ ] `brew bundle check --file=macos/Brewfile` passes

## External Drive Assumption

The external drive mounts with partitions including `~/src`. As long as auto-mount works:
- All project data in `~/src/` is already there
- Claude config at `~/src/claude` is already there
- Only the dotfiles and packages need to be restored (that's what `restore.sh` does)

GPG keys are NOT on the external drive — they live in macOS Keychain (see [GPG Key Backup](#gpg-key-backup-macos-keychain) above). Migration Assistant or a manual export is needed when moving to a new Mac.
