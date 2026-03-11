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
  setup-guide.md         # Full setup guide + GPG backup
  dotfiles/
    bash_profile, bashrc, bash/    # Shell config
    vimrc, vim/                    # Vim config + plugins
    config-nvim/                   # Neovim (lazy.nvim, copilot, LSP)
    config-kitty/                  # Kitty terminal config
    config-git/                    # Global gitignore
    w3m/                           # w3m config + keymap
```

## Key facts

- **External drive** — `~/src` partition auto-mounts; project data, Claude config, and GPG backup all live there
- **`CLAUDE_CONFIG_DIR=~/src/claude`** — Claude Code config on external drive, symlinked to `~/.claude`
- **`~/src/secrets/`** — GPG key backup, local git only, never pushed
- **Secretive** — SSH via Secure Enclave (non-transferable per machine)
- **Tailscale** — client-only, just sign in
- **OrbStack** — container runtime; `restore.sh` also bootstraps Linux VMs
