#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/dotfiles"

# --- Detect platform ---
OS="$(uname -s)"
case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported OS: $OS"; exit 1 ;;
esac
echo "==> Platform: $PLATFORM"

# --- Phase 1: Packages ---
install_packages() {
    if [[ "$PLATFORM" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            echo "==> Installing Homebrew"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        echo "==> Installing packages from Brewfile"
        HOMEBREW_NO_AUTO_UPDATE=1 brew bundle install --file="$SCRIPT_DIR/Brewfile" --no-lock
    else
        echo "==> Installing packages (apt)"
        sudo apt update
        sudo apt install -y bash neovim git w3m curl ripgrep fzf jq bat tmux
        # mise
        if ! command -v mise &>/dev/null; then
            curl https://mise.run | sh
        fi
    fi
}

# --- Phase 2: Dotfiles ---
place_dotfiles() {
    echo "==> Placing dotfiles"

    # bash
    cp -v "$DOTFILES/bash_profile" ~/.bash_profile
    cp -v "$DOTFILES/bashrc" ~/.bashrc
    mkdir -p ~/.bash
    cp -v "$DOTFILES"/bash/*.bash ~/.bash/

    # vim
    cp -v "$DOTFILES/vimrc" ~/.vimrc
    mkdir -p ~/.vim/autoload ~/.vim/colors
    cp -v "$DOTFILES/vim/autoload/plug.vim" ~/.vim/autoload/
    cp -v "$DOTFILES/vim/colors/solarized.vim" ~/.vim/colors/

    # nvim
    mkdir -p ~/.config/nvim
    rsync -a "$DOTFILES/config-nvim/" ~/.config/nvim/

    # kitty (macOS only — kitty on Linux uses different config paths sometimes)
    if [[ "$PLATFORM" == "macos" ]] && [[ -d "$DOTFILES/config-kitty" ]]; then
        mkdir -p ~/.config/kitty
        cp -v "$DOTFILES"/config-kitty/* ~/.config/kitty/
    fi

    # git
    mkdir -p ~/.config/git
    cp -v "$DOTFILES/config-git/ignore" ~/.config/git/

    # w3m
    mkdir -p ~/.w3m
    cp -v "$DOTFILES/w3m/config" ~/.w3m/
    cp -v "$DOTFILES/w3m/keymap" ~/.w3m/
}

# --- Phase 3: Dev tools ---
setup_dev_tools() {
    echo "==> Setting up dev tools"

    # Source bashrc to get mise, PATH, etc.
    set +u  # bashrc may reference unset vars
    source ~/.bashrc 2>/dev/null || true
    set -u

    # nvim plugins (lazy.nvim auto-bootstraps on first launch)
    echo "    nvim: run 'nvim' once to install plugins via lazy.nvim"

    # vim plugins
    if command -v vim &>/dev/null && [[ -f ~/.vim/autoload/plug.vim ]]; then
        echo "    vim: installing plugins"
        vim +PlugInstall +qall 2>/dev/null || true
    fi

    # npm globals
    if [[ -f "$SCRIPT_DIR/npm-globals.txt" ]] && command -v npm &>/dev/null; then
        echo "    npm: installing globals"
        xargs npm install -g < "$SCRIPT_DIR/npm-globals.txt" 2>/dev/null || true
    fi
}

# --- Phase 4: macOS preferences ---
apply_macos_defaults() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if [[ ! -f "$SCRIPT_DIR/defaults-dump.sh" ]]; then return; fi

    echo "==> Applying macOS defaults"
    bash "$SCRIPT_DIR/defaults-dump.sh"
}

# --- Phase 5: Manual steps reminder ---
print_manual_steps() {
    echo ""
    echo "=========================================="
    echo "  Manual steps remaining"
    echo "=========================================="
    echo ""

    if [[ "$PLATFORM" == "macos" ]]; then
        cat <<'MANUAL'
  1. Secretive: Open app → creates Secure Enclave key
     - Add public key to GitHub (Settings → SSH keys)
     - Add to remote servers (pezware-uno, pezware-dos)
     - Verify: ssh -T git@github.com

  2. GPG: Import key or generate new one
     gpg --import ~/src/secrets/gpg-private.asc
     gpg --import-ownertrust ~/src/secrets/gpg-ownertrust.txt
     git config --global user.signingkey <KEY_ID>
     git config --global commit.gpgsign true

  3. Auth:
     gh auth login
     gcloud init && gcloud auth login

  4. macOS Settings (cannot be scripted):
     - Caps Lock → Control (Keyboard → Keyboard Shortcuts → Modifier Keys)
     - Display scaling (Displays → choose scaling)

  5. Tailscale: Sign in (client-only)

  6. Claude: symlink ~/src/claude → ~/.claude
     ln -s ~/src/claude ~/.claude
MANUAL
    else
        cat <<'MANUAL'
  1. Auth:
     gh auth login
     gcloud init && gcloud auth login (if needed)

  2. GPG (if needed):
     gpg --import /path/to/gpg-private.asc

  3. Claude:
     npm install -g claude-code codex
MANUAL
    fi

    echo ""
    echo "==> Done. Open a new terminal to pick up changes."
}

# --- Main ---
echo ""
echo "0x58 restore — $PLATFORM"
echo ""

install_packages
place_dotfiles
setup_dev_tools
apply_macos_defaults
print_manual_steps
