# 0x58

Personal system configuration backup — quick bootstrap for macOS, Linux VMs, or a
headless Linux server.

Core workflow: kitty + bash + nvim + git + w3m + claude/codex + gcloud.

## Quick Start

```bash
./macos/restore.sh              # detects macOS vs Linux, installs everything
HEADLESS=1 ./macos/restore.sh   # ...plus laptop-as-server config (lid, battery)
```

Bare Linux machine, nothing installed yet:

```bash
bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
```

See [macos/setup-guide.md](macos/setup-guide.md) for manual steps (SSH keys, GPG, auth),
or [linux/setup-guide.md](linux/setup-guide.md) for a Debian headless install.

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

linux/
  start.sh               # Bare-metal one-liner: installs git, clones, runs restore.sh
  packages.txt           # apt base packages (dev tools come from mise, not apt)
  setup-server.sh        # Laptop-as-server: lid-close + battery charge ceiling
  setup-guide.md         # Debian netinst walkthrough, partitioning, tasksel choices

cloudflare/
  worker.js              # Serves linux/start.sh at m.pezware.com/linux-start.sh
  wrangler.toml          # Route + deploy config (wrangler comes from mise)
  README.md              # DNS setup, and why a CNAME cannot do this
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
- **Claude config** — real directory is `~/src/claude` on the external drive; `~/.claude` is a symlink pointing to it (`~/.claude → ~/src/claude`). The symlink *is* the indirection — `CLAUDE_CONFIG_DIR` is not set. Inventory sync reads through the stable `~/.claude` path. Re-link only when `~/.claude` is absent (`ln -s ~/src/claude ~/.claude`); never link `~/.claude` onto an existing symlink (creates a nested link) and never make `~/src/claude` itself a symlink (would loop).
- **Secretive** — SSH via Secure Enclave (non-transferable per machine — must be re-created on new hardware)
- **Migration Assistant** is the recommended path for new-machine setup; it transfers the login keychain so all credential restores Just Work afterwards
- **Tailscale** — client-only, just sign in
- **OrbStack** — container runtime; `restore.sh` also bootstraps Linux VMs
- **Linux package split** — apt owns the base system, `mise` owns every dev tool and
  runtime. No Homebrew on Linux: `dotfiles/mise/config.toml` is already cross-platform
  and covers ~50 of the Brewfile's formulae, so a second package manager would only
  add 1–3 GB and source builds. See [linux/setup-guide.md](linux/setup-guide.md)
- **Headless laptop server** — lid-close suspend and permanent-AC battery swelling are
  the two things that kill the project; `HEADLESS=1` handles both
- **Touch ID in tmux** — `pam-reattach` + a PAM edit needed; `restore.sh` automates it (see [setup-guide.md](macos/setup-guide.md#touch-id-for-sudo-in-tmux-pam-reattach))
