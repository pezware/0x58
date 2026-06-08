# 0x58

Personal system configuration backup — quick bootstrap for macOS or Linux VMs.

Core workflow: kitty + bash + nvim + git + w3m + claude/codex + gcloud.

## Quick Start

```bash
./macos/restore.sh    # detects macOS vs Linux, installs everything
```

See [macos/setup-guide.md](macos/setup-guide.md) for manual steps (SSH keys, GPG, auth).

## Structure

```
macos/
  restore.sh             # One-command bootstrap (macOS + Linux)
  inventory.sh           # Regenerate inventory from current system
  defaults.sh            # macOS defaults dump/apply (--dump, --dry-run)
  Brewfile               # Curated Homebrew packages
  defaults-dump.sh       # Curated defaults write commands
  apps.md                # /Applications list with source
  dev-tools.md           # mise tools, npm globals
  npm-globals.txt        # Global npm package names
  launch-agents.txt      # ~/Library/LaunchAgents listing
  shell-config.md        # Shell architecture overview
  ssh-config.md          # SSH + Secretive setup docs
  setup-guide.md         # Full setup guide + macOS Keychain GPG recovery
  dotfiles/
    bash_profile, bashrc           # Shell entrypoints
    bash/                          # Modular bash includes:
                                   #   gpg-keychain.bash    — GPG cold backup helpers
                                   #   gcloud-session.bash  — gcloud_login/logout/status
                                   #   kubectl-context.bash — per-window kube context
                                   #   plus history, prompt, glow, work_alias, etc.
    vimrc, vim/                    # Vim config + plugins
    config-nvim/                   # Neovim (lazy.nvim, copilot, LSP)
    config-kitty/                  # Kitty terminal config
    config-tmux/                   # tmux config (cross-platform; tpm + resurrect)
    config-git/                    # Global gitignore + allowed_signers
    codex/config.toml              # Codex CLI config (cli_auth_credentials_store="auto")
    kube/                          # README + exec-based GKE/EKS configs (no secrets)
    w3m/                           # w3m config + keymap
```

## Credential storage

Every credential type is at-rest encrypted. Hierarchy by what holds it:

| Tier | Backend | What's there |
|---|---|---|
| Hardware | Secure Enclave (Secretive) | SSH key (git, server access) — non-transferable per machine |
| macOS Keychain | login.keychain-db | GPG cold backup (`gpg-archive-b64`), Codex auth (`Codex Auth`), Claude Code (`Claude Code-credentials-*`), `gh` token, `glab` token (`--use-keyring`), Docker auths (`credsStore: osxkeychain`) |
| Session-only | `~/.config/gcloud/credentials.db` | gcloud refresh token — removed by `gcloud_logout` at end of work session |
| On disk | `~/.npmrc` | npm registry token (no keychain integration) |

GPG private keys are NOT in `~/.gnupg/private-keys-v1.d/` between sessions — they're restored from Keychain on demand. See [setup-guide.md → GPG Key Backup](macos/setup-guide.md#gpg-key-backup-macos-keychain) for snapshot/restore/fresh-machine flows.

## Key facts

- **External drive** — `~/src` partition auto-mounts; project data and Claude config live there
- **`CLAUDE_CONFIG_DIR=~/src/claude`** — Claude Code config on external drive, symlinked to `~/.claude`
- **Secretive** — SSH via Secure Enclave (non-transferable per machine — must be re-created on new hardware)
- **Migration Assistant** is the recommended path for new-machine setup; it transfers the login keychain so all credential restores Just Work afterwards
- **Tailscale** — client-only, just sign in
- **OrbStack** — container runtime; `restore.sh` also bootstraps Linux VMs
- **Touch ID in tmux** — `pam-reattach` + a PAM edit needed; `restore.sh` automates it (see [setup-guide.md](macos/setup-guide.md#touch-id-for-sudo-in-tmux-pam-reattach))
