#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"

mkdir -p "$DOTFILES_DIR"

# --- Brewfile ---
# Always regenerate from current brew state; mise.toml owns dev-tool versions
# and brew is reserved for system libs, GUI casks, and tools without a mise backend.
echo "==> Regenerating Brewfile from brew state"
HOMEBREW_NO_AUTO_UPDATE=1 brew bundle dump --force --file="$SCRIPT_DIR/Brewfile"
{
    grep '^tap ' "$SCRIPT_DIR/Brewfile" | sort || true
    grep '^brew ' "$SCRIPT_DIR/Brewfile" | sort || true
    grep '^cask ' "$SCRIPT_DIR/Brewfile" | sort || true
    grep '^mas ' "$SCRIPT_DIR/Brewfile" | sort || true
    grep '^vscode ' "$SCRIPT_DIR/Brewfile" | sort || true
} > "$SCRIPT_DIR/Brewfile.sorted"
mv "$SCRIPT_DIR/Brewfile.sorted" "$SCRIPT_DIR/Brewfile"

# --- apps.md ---
echo "==> Generating apps.md"
{
    echo "# Installed Applications"
    echo ""
    echo "Generated: $(date -u +%Y-%m-%d)"
    echo ""

    # Get cask-installed apps for cross-reference
    cask_list=$(brew list --cask 2>/dev/null || true)

    echo "| Application | Source |"
    echo "|---|---|"
    for app in /Applications/*.app; do
        [[ -d "$app" ]] || continue
        name="$(basename "$app" .app)"
        # Check if it came from a cask
        cask_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if echo "$cask_list" | grep -qi "^${cask_name}$" 2>/dev/null; then
            echo "| $name | brew cask |"
        else
            echo "| $name | manual/App Store |"
        fi
    done
} > "$SCRIPT_DIR/apps.md"

# --- dev-tools.md ---
echo "==> Generating dev-tools.md"
# mise activates only in interactive shells; eval here so this script picks it up
eval "$(mise activate bash)" 2>/dev/null || true
{
    echo "# Development Tools"
    echo ""
    echo "Generated: $(date -u +%Y-%m-%d)"
    echo ""
    echo "Source of truth: [\`../dotfiles/mise/config.toml\`](../dotfiles/mise/config.toml)"
    echo "(symlinked to \`~/.config/mise/config.toml\`)"
    echo ""

    echo "## mise-managed tools"
    echo ""
    echo '```'
    mise ls --installed 2>/dev/null || echo "mise not available"
    echo '```'
    echo ""

    echo "## npm globals"
    echo ""
    echo '```'
    if command -v npm >/dev/null 2>&1; then
        npm list -g --depth=0 2>/dev/null
    else
        echo "(none — node/npm provided via mise; no global packages)"
    fi
    echo '```'
    echo ""

    echo "## Key tool notes"
    echo ""
    echo "- **mise** — single source of truth for dev tools (node, go, terraform, kubectl, etc.)"
    echo "- **brew** — system libs, GUI casks, macOS-specific tools only"
    echo "- **OrbStack** — container runtime (Docker-compatible, paying user)"
    echo "- **Secretive** — SSH agent backed by Secure Enclave hardware keys"
    echo "- **GPG signing** enabled for git commits"
    echo "- **Release-age buffer** — 3 days for both mise and pnpm/npm"
} > "$SCRIPT_DIR/dev-tools.md"

# --- npm-globals.txt ---
echo "==> Generating npm-globals.txt"
if command -v npm >/dev/null 2>&1; then
    npm list -g --depth=0 --parseable 2>/dev/null \
        | tail -n +2 \
        | xargs -I{} basename {} \
        | sort \
        > "$SCRIPT_DIR/npm-globals.txt"
else
    echo "(none — npm via mise, no global packages)" > "$SCRIPT_DIR/npm-globals.txt"
fi

# --- launch-agents.txt ---
echo "==> Generating launch-agents.txt"
ls ~/Library/LaunchAgents/ 2>/dev/null > "$SCRIPT_DIR/launch-agents.txt" || echo "No LaunchAgents" > "$SCRIPT_DIR/launch-agents.txt"

# --- dotfiles (bash) ---
echo "==> Copying bash dotfiles"
[[ -f ~/.bash_profile ]] && cp -p ~/.bash_profile "$DOTFILES_DIR/bash_profile"
[[ -f ~/.bashrc ]] && cp -p ~/.bashrc "$DOTFILES_DIR/bashrc"

if [[ -d ~/.bash ]]; then
    mkdir -p "$DOTFILES_DIR/bash"
    for f in ~/.bash/*; do
        [[ -f "$f" ]] && cp -p "$f" "$DOTFILES_DIR/bash/$(basename "$f")"
    done
fi

# --- app configs ---
echo "==> Copying app configs"

# vim/nvim
[[ -f ~/.vimrc ]] && cp -p ~/.vimrc "$DOTFILES_DIR/vimrc"
if [[ -d ~/.vim ]]; then
    mkdir -p "$DOTFILES_DIR/vim/autoload" "$DOTFILES_DIR/vim/colors"
    [[ -f ~/.vim/autoload/plug.vim ]] && cp -p ~/.vim/autoload/plug.vim "$DOTFILES_DIR/vim/autoload/plug.vim"
    [[ -f ~/.vim/colors/solarized.vim ]] && cp -p ~/.vim/colors/solarized.vim "$DOTFILES_DIR/vim/colors/solarized.vim"
fi
if [[ -d ~/.config/nvim ]]; then
    rsync -a --exclude='lazy-lock.json' --exclude='*~' ~/.config/nvim/ "$DOTFILES_DIR/config-nvim/"
fi

# kitty
if [[ -d ~/.config/kitty ]]; then
    mkdir -p "$DOTFILES_DIR/config-kitty"
    [[ -f ~/.config/kitty/kitty.conf ]] && cp -p ~/.config/kitty/kitty.conf "$DOTFILES_DIR/config-kitty/kitty.conf"
    [[ -f ~/.config/kitty/my-session.conf ]] && cp -p ~/.config/kitty/my-session.conf "$DOTFILES_DIR/config-kitty/my-session.conf"
    # Theme reference (just the include, not the full theme repo)
fi

# git
if [[ -d ~/.config/git ]]; then
    mkdir -p "$DOTFILES_DIR/config-git"
    [[ -f ~/.config/git/ignore ]] && cp -p ~/.config/git/ignore "$DOTFILES_DIR/config-git/ignore"
    [[ -f ~/.config/git/allowed_signers ]] && cp -p ~/.config/git/allowed_signers "$DOTFILES_DIR/config-git/allowed_signers"
    [[ -f ~/.config/git/personal ]] && cp -p ~/.config/git/personal "$DOTFILES_DIR/config-git/personal"
fi

# kube (README + exec-based GKE/EKS configs only; orbstack/kind have embedded TLS creds)
if [[ -d ~/.kube ]]; then
    mkdir -p "$DOTFILES_DIR/kube/configs"
    [[ -f ~/.kube/README.md ]] && cp -p ~/.kube/README.md "$DOTFILES_DIR/kube/README.md"
    for d in ~/.kube/configs/gke-* ~/.kube/configs/eks-*; do
        [[ -d "$d" ]] || continue
        name=$(basename "$d")
        # Skip if config has embedded credentials (defense in depth)
        if [[ -f "$d/config" ]] && ! grep -qE '(client-(key|certificate)-data|^[[:space:]]*token:)' "$d/config"; then
            mkdir -p "$DOTFILES_DIR/kube/configs/$name"
            cp -p "$d/config" "$DOTFILES_DIR/kube/configs/$name/config"
        fi
    done
fi

# codex (config only — auth.json, sessions, logs, history are not tracked)
if [[ -f ~/.codex/config.toml ]]; then
    mkdir -p "$DOTFILES_DIR/codex"
    cp -p ~/.codex/config.toml "$DOTFILES_DIR/codex/config.toml"
fi

# w3m (config + keymap only, skip cache/history)
if [[ -d ~/.w3m ]]; then
    mkdir -p "$DOTFILES_DIR/w3m"
    [[ -f ~/.w3m/config ]] && cp -p ~/.w3m/config "$DOTFILES_DIR/w3m/config"
    [[ -f ~/.w3m/keymap ]] && cp -p ~/.w3m/keymap "$DOTFILES_DIR/w3m/keymap"
fi

# ~/bin scripts tracked individually (only those we want versioned — not the whole dir)
[[ -f ~/bin/external-drives-mount.sh ]] && cp -p ~/bin/external-drives-mount.sh "$SCRIPT_DIR/external-drives-mount.sh"

echo "==> Done. Review generated files in $SCRIPT_DIR/"
