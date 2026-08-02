#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/dotfiles"
LINUX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/linux"

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
        # apt owns only the base system; dev tools come from mise
        # (dotfiles/mise/config.toml, already cross-platform). Keeping the two
        # lists disjoint is why the package set lives in a file rather than
        # inline here — see the header of linux/packages.txt.
        if [[ ! -f "$LINUX_DIR/packages.txt" ]]; then
            echo "ERROR: missing $LINUX_DIR/packages.txt" >&2
            exit 1
        fi
        echo "==> Installing packages (apt) from linux/packages.txt"
        local pkgs
        pkgs=$(grep -vE '^[[:space:]]*(#|$)' "$LINUX_DIR/packages.txt" | awk '{print $1}')
        sudo apt update
        # shellcheck disable=SC2086  # word splitting is intended: one package per line
        sudo apt install -y $pkgs

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

    # tmux (cross-platform — config has no OS-hardcoded paths)
    if [[ -d "$DOTFILES/config-tmux" ]]; then
        mkdir -p ~/.config/tmux
        cp -v "$DOTFILES/config-tmux/tmux.conf" ~/.config/tmux/tmux.conf
        # alert-bell hook posts a desktop notification via this script; the
        # hook references it by path, so it must land next to the config.
        if [[ -f "$DOTFILES/config-tmux/notify-bell.sh" ]]; then
            cp -v "$DOTFILES/config-tmux/notify-bell.sh" ~/.config/tmux/notify-bell.sh
            chmod +x ~/.config/tmux/notify-bell.sh
        fi
        # `prefix + C` capture binding writes to ~/tmp — make sure it exists.
        # (On the primary macOS box ~/tmp is a symlink to the external drive;
        #  mkdir -p is a no-op when the target already exists.)
        mkdir -p ~/tmp
    fi

    # kitty (macOS only — kitty on Linux uses different config paths sometimes)
    if [[ "$PLATFORM" == "macos" ]] && [[ -d "$DOTFILES/config-kitty" ]]; then
        mkdir -p ~/.config/kitty
        cp -v "$DOTFILES"/config-kitty/* ~/.config/kitty/
    fi

    # git
    mkdir -p ~/.config/git
    cp -v "$DOTFILES/config-git/ignore" ~/.config/git/
    # allowed_signers is machine-specific (Secretive key) — copy as reference,
    # but it needs regeneration on new machines (see setup-guide.md)
    [[ -f "$DOTFILES/config-git/allowed_signers" ]] && cp -v "$DOTFILES/config-git/allowed_signers" ~/.config/git/
    [[ -f "$DOTFILES/config-git/personal" ]] && cp -v "$DOTFILES/config-git/personal" ~/.config/git/

    # w3m
    mkdir -p ~/.w3m
    cp -v "$DOTFILES/w3m/config" ~/.w3m/
    cp -v "$DOTFILES/w3m/keymap" ~/.w3m/

    # codex (config only; auth lands in macOS Keychain via cli_auth_credentials_store="auto")
    if [[ -f "$DOTFILES/codex/config.toml" ]]; then
        mkdir -p ~/.codex
        cp -v "$DOTFILES/codex/config.toml" ~/.codex/config.toml
    fi

    # ssh config fragment for tailnet nodes (macOS side — this is the client).
    #
    # Placed as an Include fragment so ~/.ssh/config keeps its private hosts and
    # stays out of git, while the reproducible devbox/k8s entries are versioned.
    # The Include line is prepended, because ssh takes the FIRST value it finds
    # for each keyword — appending it after an existing `Host *` block would let
    # those catch-all settings win over ours.
    if [[ "$PLATFORM" == "macos" ]] && [[ -f "$DOTFILES/ssh/config.d/0x58-devbox" ]]; then
        mkdir -p ~/.ssh/config.d && chmod 700 ~/.ssh
        cp -v "$DOTFILES/ssh/config.d/0x58-devbox" ~/.ssh/config.d/0x58-devbox
        chmod 600 ~/.ssh/config.d/0x58-devbox
        touch ~/.ssh/config && chmod 600 ~/.ssh/config
        if ! grep -qE '^\s*Include\s+~?/?\.?ssh/config\.d/\*|^\s*Include\s+config\.d/\*' ~/.ssh/config; then
            echo "    adding Include line to ~/.ssh/config (backup: config.bak-0x58)"
            cp ~/.ssh/config ~/.ssh/config.bak-0x58
            printf 'Include ~/.ssh/config.d/*\n\n%s' "$(cat ~/.ssh/config)" > ~/.ssh/config.tmp
            mv ~/.ssh/config.tmp ~/.ssh/config
            chmod 600 ~/.ssh/config
        fi
    fi

    # Agent sandbox hardening — Linux only.
    #
    # On the Mac, Claude Code uses seatbelt and credentials live in the Keychain.
    # On a remote box both subscription refresh tokens sit in plaintext files, so
    # the sandbox is what stands between an injected agent and those tokens.
    # See linux/sandbox.md for the posture and its deliberate trade-offs.
    if [[ "$PLATFORM" == "linux" ]]; then
        if [[ -f "$LINUX_DIR/claude-settings.json" ]]; then
            mkdir -p ~/.claude
            if [[ -f ~/.claude/settings.json ]]; then
                # Never clobber existing settings — a silent overwrite here could
                # drop hooks or permissions the user depends on. Land it beside
                # the real file and make the merge an explicit decision.
                cp -v "$LINUX_DIR/claude-settings.json" ~/.claude/settings.0x58-sandbox.json
                echo "    NOTE: ~/.claude/settings.json exists — merge sandbox block from settings.0x58-sandbox.json"
            else
                cp -v "$LINUX_DIR/claude-settings.json" ~/.claude/settings.json
            fi
        fi
        if [[ -f "$LINUX_DIR/codex-devbox.config.toml" ]]; then
            mkdir -p ~/.codex
            cp -v "$LINUX_DIR/codex-devbox.config.toml" ~/.codex/devbox.config.toml
        fi
    fi

    # ~/bin scripts (macOS only — external-drives-mount.sh is the boot-time mounter for AchtungAndy)
    if [[ "$PLATFORM" == "macos" ]] && [[ -f "$SCRIPT_DIR/external-drives-mount.sh" ]]; then
        mkdir -p ~/bin
        cp -v "$SCRIPT_DIR/external-drives-mount.sh" ~/bin/external-drives-mount.sh
        chmod +x ~/bin/external-drives-mount.sh
        # Login Item registration is GUI-only (BTM database) — see macos/external-drives.md
    fi

    # kube (README + exec-based GKE/EKS configs; kind/orbstack regenerated via kube-setup-* commands)
    if [[ -d "$DOTFILES/kube" ]]; then
        mkdir -p ~/.kube/configs
        [[ -f "$DOTFILES/kube/README.md" ]] && cp -v "$DOTFILES/kube/README.md" ~/.kube/README.md
        if [[ -d "$DOTFILES/kube/configs" ]]; then
            for d in "$DOTFILES/kube/configs"/*/; do
                [[ -d "$d" ]] || continue
                name=$(basename "$d")
                mkdir -p ~/.kube/configs/"$name"
                cp -v "$d/config" ~/.kube/configs/"$name/config"
            done
        fi
    fi
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

    # tmux: clone tpm so resurrect/continuum (and any future plugins) can be installed.
    # Config lives at ~/.config/tmux/tmux.conf, so TPM installs plugins to
    # ~/.config/tmux/plugins/ — keep tpm itself there too (the `run` line in
    # tmux.conf points at this path). Cloning to ~/.tmux/plugins splits the
    # plugin dir and silently breaks loading.
    # User installs the plugins from inside tmux via  prefix + I.
    if [[ ! -d ~/.config/tmux/plugins/tpm ]]; then
        echo "    tmux: cloning tpm (run 'prefix + I' inside tmux to install plugins)"
        git clone --depth 1 https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
    fi

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

# --- Phase 4a: PAM (Touch ID for sudo, including inside tmux) ---
# pam-reattach (from Brewfile) is inert until wired into the PAM stack.
# Without it, Touch ID works for sudo in a fresh terminal but silently
# falls back to password inside tmux. We write to /etc/pam.d/sudo_local
# (already included by /etc/pam.d/sudo) so the recipe survives macOS
# major-version upgrades — unlike editing /etc/pam.d/sudo directly.
setup_pam_touchid() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if [[ ! -f /opt/homebrew/lib/pam/pam_reattach.so ]]; then return; fi
    # idempotent: skip if already wired in either file
    if grep -qs pam_reattach /etc/pam.d/sudo /etc/pam.d/sudo_local 2>/dev/null; then
        echo "==> PAM Touch-ID: already configured (pam_reattach present)"
        return
    fi
    echo "==> PAM Touch-ID: writing /etc/pam.d/sudo_local (sudo prompt incoming)"
    sudo tee /etc/pam.d/sudo_local >/dev/null <<'PAM'
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
PAM
}

# --- Phase 4: macOS preferences ---
apply_macos_defaults() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if [[ ! -f "$SCRIPT_DIR/defaults-dump.sh" ]]; then return; fi

    echo "==> Applying macOS defaults"
    bash "$SCRIPT_DIR/defaults-dump.sh"
}

# --- Phase 4b: Keyboard shortcuts (Mission Control Space switching) ---
# Lives in a separate script because com.apple.symbolichotkeys is a nest of
# dicts that defaults-dump.sh can't represent, and the numbered "Switch to
# Desktop N" shortcuts ship disabled by default.
apply_keyboard_shortcuts() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if [[ ! -f "$SCRIPT_DIR/keyboard-shortcuts.sh" ]]; then return; fi

    bash "$SCRIPT_DIR/keyboard-shortcuts.sh"
}

# --- Phase 4c: Linux headless server (laptop-as-server) ---
# Lid-close suspend and permanent-AC battery swelling are the two failure modes
# that end a laptop-server project. Both need root, so this is opt-in via
# HEADLESS=1 rather than running on every Linux box (VMs and containers have
# neither a lid nor a battery).
setup_linux_server() {
    if [[ "$PLATFORM" != "linux" ]]; then return; fi
    if [[ "${HEADLESS:-0}" != "1" ]]; then
        echo "==> Headless server config: skipped (re-run with HEADLESS=1 to enable)"
        return
    fi
    if [[ ! -x "$LINUX_DIR/setup-server.sh" ]]; then
        echo "ERROR: $LINUX_DIR/setup-server.sh missing or not executable" >&2
        exit 1
    fi
    bash "$LINUX_DIR/setup-server.sh"
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
     - Add public key to GitHub as AUTH key (Settings → SSH keys)
     - Add public key to GitHub as SIGNING key (same page, different type)
     - Add to remote servers (pezware-uno, pezware-dos)
     - Verify: ssh -T git@github.com

  2. Commit signing (SSH via Secretive):
     git config --global gpg.format ssh
     git config --global user.signingkey "key::$(ssh-add -L)"
     git config --global commit.gpgsign true
     echo "$(git config user.email) $(ssh-add -L)" > ~/.config/git/allowed_signers
     git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

  3. Auth:
     gh auth login
     gcloud init && gcloud auth login

  4. Kubernetes local clusters (TLS-cred configs are NOT tracked):
     kube-setup-orbstack         # imports OrbStack k8s context (after OrbStack is running)
     kube-setup-kind iden2-dev   # if you have a kind cluster
     kube-refresh                # rebuilds merged KUBECONFIG

  5. macOS Settings (cannot be scripted):
     - Caps Lock → Control (Keyboard → Keyboard Shortcuts → Modifier Keys)
     - Display scaling (Displays → choose scaling)

  6. Tailscale: Sign in (client-only)

  7. Claude: symlink ~/.claude → ~/src/claude (real dir is ~/src/claude)
     # only link when ~/.claude is absent — never onto an existing symlink (nested
     # link) and never make ~/src/claude itself a symlink (loop)
     [ -e ~/.claude ] || [ -L ~/.claude ] || ln -s ~/src/claude ~/.claude
MANUAL
    else
        cat <<'MANUAL'
  1. Auth:
     gh auth login
     gcloud init && gcloud auth login (if needed)

  2. GPG (if needed):
     gpg --import /path/to/gpg-private.asc

  3. Claude (native installer; codex comes from mise config):
     curl -fsSL https://claude.ai/install.sh | bash

  4. mise tools (config is symlinked from the 0x58 repo):
     ln -sf ~/src/public/0x58/dotfiles/mise/config.toml ~/.config/mise/config.toml
     mise trust ~/.config/mise/config.toml && mise install

  5. SSH access from the Mac (Secretive key stays on the Mac — only the
     PUBLIC half comes here, so the Secure Enclave key is never transferred):
     mkdir -p ~/.ssh && chmod 700 ~/.ssh
     # on the Mac:  ssh-add -L | pbcopy    then paste into:
     vim ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

  6. Tailscale (reach the box without port-forwarding):
     curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --ssh

  7. Headless server config (laptop-as-server only — lid + battery):
     HEADLESS=1 ./macos/restore.sh     # or: bash linux/setup-server.sh
     See linux/setup-guide.md for the install-time choices that can't be scripted.
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
setup_pam_touchid
setup_linux_server
apply_macos_defaults
apply_keyboard_shortcuts
print_manual_steps
