#!/usr/bin/env bash
#
# 0x58 bare-metal bootstrap — takes a fresh Debian install to a working box.
#
#   bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
#
# Use that form rather than `curl ... | bash`: piping puts this script on stdin,
# so anything downstream that reads from the terminal (a sudo re-prompt, an apt
# conffile question) consumes the script's own bytes instead of your keystrokes.
#
# Everything below lives in a function and `main` is called on the LAST line.
# That MITIGATES truncation but does not eliminate it: a cut anywhere inside a
# function body is a syntax error and nothing runs, but a cut landing in the
# final few bytes — right after `main` — still yields a valid call. Command
# substitution also discards curl's exit status, so `bash -c` never learns the
# download failed. When that matters, download and verify first:
#
#   curl -fsSL -o /tmp/start.sh https://m.pezware.com/linux-start.sh && bash /tmp/start.sh
#
# Env overrides:  REPO_URL  REPO_DIR  REPO_BRANCH  HEADLESS=1
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/pezware/0x58.git}"
REPO_DIR="${REPO_DIR:-$HOME/src/public/0x58}"
REPO_BRANCH="${REPO_BRANCH:-main}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

preflight() {
    [[ "$(uname -s)" == "Linux" ]] \
        || die "Linux only (got $(uname -s)). On macOS: clone the repo and run macos/restore.sh."
    [[ "${EUID:-$(id -u)}" -ne 0 ]] \
        || die "do not run as root — restore.sh writes to \$HOME and calls sudo only where needed."
    command -v apt-get >/dev/null \
        || die "no apt-get — this bootstrap targets Debian/Ubuntu."
    command -v sudo >/dev/null \
        || die "no sudo — as root: apt install sudo && adduser $USER sudo, then log back in."
}

install_bootstrap_deps() {
    # The bare minimum to fetch the repo. Everything else is installed by
    # restore.sh from linux/packages.txt (apt) and dotfiles/mise/config.toml.
    if command -v git >/dev/null; then
        log "git already present — skipping bootstrap deps"
        return
    fi
    log "installing git + ca-certificates (sudo prompt incoming)"
    sudo apt-get update -qq
    sudo apt-get install -y -qq git ca-certificates
}

fetch_repo() {
    if [[ -d "$REPO_DIR/.git" ]]; then
        log "updating existing checkout at $REPO_DIR"
        git -C "$REPO_DIR" fetch --quiet origin "$REPO_BRANCH"
        # --ff-only so a re-run can never silently merge, rebase, or clobber
        # local edits; a diverged checkout is a stop-and-look, not an auto-fix.
        git -C "$REPO_DIR" merge --ff-only "origin/$REPO_BRANCH" \
            || die "$REPO_DIR has local changes blocking a fast-forward — resolve them, then re-run."
    else
        log "cloning $REPO_URL -> $REPO_DIR"
        mkdir -p "$(dirname "$REPO_DIR")"
        git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
        # Fetch over HTTPS (public repo, no credential needed at bootstrap) but
        # PUSH over SSH, so it goes through the forwarded Secure Enclave key and
        # needs a Touch ID tap. Otherwise the first push asks for a GitHub
        # username and there is no credential on the box to answer with.
        git -C "$REPO_DIR" remote set-url --push origin "${REPO_PUSH_URL:-git@github.com:pezware/0x58.git}"
    fi
}

run_restore() {
    local restore="$REPO_DIR/macos/restore.sh"
    [[ -f "$restore" ]] || die "missing $restore — is REPO_BRANCH=$REPO_BRANCH correct?"
    log "handing off to restore.sh"
    echo ""
    # exec so restore.sh owns the terminal (and inherits HEADLESS from our env).
    exec bash "$restore"
}

main() {
    echo ""
    echo "0x58 bootstrap — $REPO_URL ($REPO_BRANCH)"
    echo "  target: $REPO_DIR"
    if [[ "${HEADLESS:-0}" == "1" ]]; then
        echo "  HEADLESS=1 — laptop-as-server config (lid, battery) will run"
    fi
    echo ""

    preflight
    install_bootstrap_deps
    fetch_repo
    run_restore
}

main "$@"
