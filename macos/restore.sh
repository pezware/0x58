#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$SCRIPT_DIR/dotfiles"
LINUX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/linux"
BIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/bin"

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

        # Compose provider — deliberately NOT in packages.txt, because it is the
        # one package that must not bring its Recommends. docker-compose
        # recommends docker-cli, which would put a real /usr/bin/docker on PATH
        # that talks to /var/run/docker.sock (absent on this rootless box) and
        # shadows the podman shim agents are told to use. Two confusing failures
        # for the price of one convenience.
        #
        # docker-compose over podman-compose: podman prefers it when both are
        # present, and it is the reference Compose-spec implementation, so an
        # existing docker-compose.yml runs unmodified. --no-install-recommends
        # keeps it to a single static binary depending only on libc6.
        if ! command -v docker-compose &>/dev/null; then
            echo "==> Installing compose provider (docker-compose, no recommends)"
            sudo apt install -y --no-install-recommends docker-compose
        fi

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

    # nvim — macOS only as of 2026-08-05. The devbox uses apt's vim, so shipping
    # a lazy.nvim tree there placed ~40 KB of config for an editor that is no
    # longer installed, and every `vim` on that box now resolves to /usr/bin/vim.
    if [[ "$PLATFORM" == "macos" ]]; then
        mkdir -p ~/.config/nvim
        rsync -a "$DOTFILES/config-nvim/" ~/.config/nvim/
    fi

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

    # npm / pnpm supply-chain cooldown.
    #
    # Two files because the two tools disagree on both the key and the unit, and
    # because only one of them is readable by a sandboxed agent: ~/.npmrc is on
    # the credentials deny list (it is where npm auth lands), while pnpm 11 keeps
    # non-auth settings in ~/.config/pnpm/config.yaml, which is not denied. See
    # the headers in both files before changing either.
    cp -v "$DOTFILES/npmrc" ~/.npmrc
    mkdir -p ~/.config/pnpm
    cp -v "$DOTFILES/pnpm/config.yaml" ~/.config/pnpm/config.yaml

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
        # Agent instructions. Without these, Claude on a remote box runs generic —
        # no worktree rule, no commit conventions, none of the Operations Runbook.
        #
        # Linux only, and deliberately so: on the Mac ~/.claude is a symlink to the
        # external drive and IS the source of truth, so writing this copy there
        # would overwrite live content with a repo snapshot.
        #
        # NOTE: the tracked copy is SANITIZED — the iden2-com ticket runbook is
        # stripped because this repository is public. Push the full version to a
        # node separately (see dev/nodes/README.md → "Private agent instructions").
        if [[ -f "$DOTFILES/claude/CLAUDE.md" ]]; then
            mkdir -p ~/.claude
            # Never clobber a fuller local copy. The tracked file is sanitized, so
            # a plain cp on a box that already received the full version silently
            # DOWNGRADES it -- the agent quietly loses the ticket runbook and only
            # a byte count would show it. Copy when absent; otherwise leave it be.
            if [[ ! -f ~/.claude/CLAUDE.md ]]; then
                cp -v "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md
            elif ! cmp -s "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md; then
                echo "    claude: kept existing CLAUDE.md ($(wc -c < ~/.claude/CLAUDE.md) bytes) — tracked copy is sanitized"
            fi
            # Codex reads AGENTS.md where Claude reads CLAUDE.md. Symlink rather
            # than copy so the two can never drift apart on the same machine.
            mkdir -p ~/.codex
            ln -sfn ~/.claude/CLAUDE.md ~/.codex/AGENTS.md
            echo "    linked ~/.codex/AGENTS.md -> ~/.claude/CLAUDE.md"
        fi

        # Skills, slash commands and the knowledge book are tracked here and were
        # simply never placed -- a rebuilt box came back with CLAUDE.md but no
        # skills at all, which degrades quietly: the agent just never offers them.
        # ~/.claude/agents is deliberately absent; inventory.sh does not capture it
        # yet, so there is nothing to restore from (see dev/nodes/README.md).
        for _d in skills commands knowledge hooks; do
            if [[ -d "$DOTFILES/claude/$_d" ]]; then
                mkdir -p ~/.claude/"$_d"
                rsync -a "$DOTFILES/claude/$_d/" ~/.claude/"$_d"/
                echo "    claude: $_d ($(find "$DOTFILES/claude/$_d" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') entries)"
            fi
        done
        unset _d

        # Settings: MERGE the keys this repo owns, rather than staging a copy and
        # hoping someone merges it.
        #
        # This used to land settings.0x58-sandbox.json beside the live file and
        # print a NOTE. The guard was right — a blind overwrite would drop hooks
        # and permissions Claude Code writes itself — but the consequence was that
        # settings changes NEVER applied. It swallowed a credential change on
        # 2026-08-04 and a SessionStart hook plus an allowlist removal on
        # 2026-08-05, each time silently, each time discovered only when an agent
        # hit the behaviour the change was meant to fix. A guard whose failure mode
        # is "nothing happened and nobody was told" is worse than the clobber it
        # prevents.
        #
        # So merge narrowly instead. `sandbox` and `autoMode` are wholly owned by
        # this repo and are replaced. Under `permissions` only `defaultMode` is
        # ours; under `hooks`, only OUR SessionStart entry is replaced -- matched
        # by its command path -- so hand-added hooks and every other event
        # survive. Anything else in the file is untouched by construction.
        #
        # The merge is an ALLOWLIST of keys, which means a key this repo starts
        # owning later is silently dropped until it is added here too. That is the
        # same "nothing happened and nobody was told" failure the staged copy had.
        # If you add a key to claude-settings.json, add it below in the same commit.
        if [[ -f "$LINUX_DIR/claude-settings.json" ]]; then
            mkdir -p ~/.claude
            if [[ ! -f ~/.claude/settings.json ]]; then
                cp -v "$LINUX_DIR/claude-settings.json" ~/.claude/settings.json
            else
                SETTINGS_SRC="$LINUX_DIR/claude-settings.json" python3 - <<'PY'
import json, os, shutil, sys

live_p = os.path.expanduser('~/.claude/settings.json')
repo = json.load(open(os.environ['SETTINGS_SRC']))
try:
    live = json.load(open(live_p))
except Exception as e:
    print(f"    claude: settings.json is not valid JSON ({e}) — left alone", file=sys.stderr)
    sys.exit(0)

before = json.dumps(live, sort_keys=True)
shutil.copy2(live_p, live_p + '.bak-restore')

changed = []
if live.get('sandbox') != repo.get('sandbox'):
    live['sandbox'] = repo['sandbox']
    changed.append('sandbox')

# `autoMode` is wholly owned by this repo, like `sandbox`, so it is replaced
# rather than merged. Claude Code never writes this key itself.
if repo.get('autoMode') is not None and live.get('autoMode') != repo['autoMode']:
    live['autoMode'] = repo['autoMode']
    changed.append('autoMode')

# Under `permissions` we own ONLY defaultMode. `allow`/`deny`/`ask` accumulate
# entries Claude Code writes as the human answers prompts, and replacing the
# block wholesale would silently discard them -- the same class of bug the
# staged-copy approach had, one level down.
repo_mode = repo.get('permissions', {}).get('defaultMode')
if repo_mode and live.get('permissions', {}).get('defaultMode') != repo_mode:
    live.setdefault('permissions', {})['defaultMode'] = repo_mode
    changed.append('permissions.defaultMode')

# Replace only the entry whose command we install; leave every other hook alone.
ours = {h['hooks'][0]['command']
        for h in repo.get('hooks', {}).get('SessionStart', [])
        if h.get('hooks')}
if ours:
    kept = [h for h in live.get('hooks', {}).get('SessionStart', [])
            if not (h.get('hooks') and h['hooks'][0].get('command') in ours)]
    merged = kept + repo['hooks']['SessionStart']
    if live.get('hooks', {}).get('SessionStart') != merged:
        live.setdefault('hooks', {})['SessionStart'] = merged
        changed.append('hooks.SessionStart')

if json.dumps(live, sort_keys=True) == before:
    print('    claude: settings already in sync')
else:
    with open(live_p, 'w') as fh:
        json.dump(live, fh, indent=2)
        fh.write('\n')
    print(f"    claude: settings merged ({', '.join(changed)}) — backup at settings.json.bak-restore")
PY
            fi
        fi
        # Codex hardening goes into the REAL config, not a profile. A profile has
        # to be selected (`-p devbox`), which we did via a shell alias — and
        # aliases exist only in interactive shells, so Claude Code's Bash tool
        # and any script got the unhardened defaults while the config looked
        # hardened. Defaults belong in the config file.
        #
        # Prepended: the shared config ends in [projects."..."] tables, and bare
        # keys after a table header belong to that table.
        #
        # Three cases, because restore.sh must be safely RE-runnable. Codex writes
        # its own tables into this file — marketplaces, memories, plugins, hooks —
        # so regenerating it from the repo copy on a live box would destroy them.
        if [[ -f "$LINUX_DIR/codex-hardening.toml" ]]; then
            mkdir -p ~/.codex
            if [[ ! -f ~/.codex/config.toml ]]; then
                # Fresh node: hardening + the shared config from the repo.
                cat "$LINUX_DIR/codex-hardening.toml" "$DOTFILES/codex/config.toml" > ~/.codex/config.toml
                echo "    codex: hardened config written (sandbox_mode + network_access=false)"
            elif grep -q '^sandbox_mode' ~/.codex/config.toml; then
                echo "    codex: config already hardened — left alone"
            else
                # Re-run on a live box: prepend to what is actually on disk, so
                # everything Codex wrote for itself survives.
                cp ~/.codex/config.toml ~/.codex/config.toml.bak-0x58
                cat "$LINUX_DIR/codex-hardening.toml" ~/.codex/config.toml.bak-0x58 > ~/.codex/config.toml
                echo "    codex: hardening prepended to existing config (backup: config.toml.bak-0x58)"
            fi
        fi

        # Git identity. Without it every commit on the box dies with "Please tell
        # me who you are", which is how an agent ended up hand-setting repo-local
        # config just to get a commit through.
        #
        # Only set when absent, so a machine-specific choice is never clobbered.
        #
        # NOTE this differs from the Mac deliberately. There the global identity is
        # the work one and ~/src/public/ overrides to personal; here personal is the
        # default, so commits to the iden2 repos carry it too. If that matters, add:
        #   git config --global includeIf.gitdir:~/src/iden2/.path ~/.config/git/work
        #
        # commit.gpgsign is deliberately NOT enabled. Signing needs the forwarded
        # SSH agent, and the agent socket is AF_UNIX — which Claude Code's sandbox
        # refuses at socket(). Forcing it would make every agent commit fail hard
        # rather than merely be unsigned. Sign from your own shell with `git -S`.
        git config --global --get user.name  >/dev/null 2>&1 || git config --global user.name  "arbeitandy"
        git config --global --get user.email >/dev/null 2>&1 || git config --global user.email "andy@pezware.com"

        # SSH-based commit signing through the FORWARDED agent, so the private key
        # never reaches this machine. All three repos enforce required_signatures
        # via rulesets, so unsigned commits simply cannot land on main.
        #
        # A devbox-local signing key was considered and rejected: ~/.ssh and
        # ~/.gnupg are in the sandbox's denyRead, so an agent could not read it
        # anyway — and putting one somewhere readable would let any agent-run
        # command exfiltrate it, which destroys the only thing a signature proves.
        # On Linux the shared value is not merely wrong, it is unusable. The Mac
        # stores `key::<pubkey>`, which names a key held by an AGENT — correct
        # there, because Secretive keeps it in the Secure Enclave and there is no
        # file to point at. The devbox is the mirror image: a key on disk and no
        # agent. Given `key::` it fails with "Couldn't find key in agent?" no
        # matter which key is named, so it must point at a PATH instead.
        #
        # This supersedes the rejection above: the box now has its own signing
        # key, registered on GitHub, so it signs without the Mac. ~/.ssh stays in
        # the sandbox's denyRead, which is what kept the original objection --
        # that any agent-run command could exfiltrate it -- from applying.
        if [[ "$PLATFORM" == "linux" && -f ~/.ssh/devbox_agent ]]; then
            # TWO keys, one per GitHub account, and pairing them wrong is silent.
            # GitHub resolves a signature by commit email -> account -> THAT
            # account's signing keys, so the key must belong to the account that
            # owns the email, not merely to you:
            #
            #   global default  andy@pezware.com -> achtungandy -> devbox_agent_personal
            #   ~/src/iden2/    andy@iden2.com   -> arbeitandy  -> devbox_agent   (below)
            #
            # This line named devbox_agent until 2026-08-04, which signed every
            # public-repo commit with the WORK account's key. Nothing failed: the
            # push succeeded, `git log %G?` said G, and GitHub alone reported
            # `unknown_key` on the PR. Falls back to devbox_agent when the personal
            # key is absent, which is worse but still signs.
            if [[ -f ~/.ssh/devbox_agent_personal ]]; then
                git config --global user.signingkey ~/.ssh/devbox_agent_personal
                echo "    git: signing with the PERSONAL devbox key (achtungandy owns andy@pezware.com)"
            else
                git config --global user.signingkey ~/.ssh/devbox_agent
                echo "    git: signing with on-disk devbox key (no personal key present)"
            fi

            # ssh only offers DEFAULT identity names (id_ed25519, id_rsa, ...).
            # devbox_agent is not one, so without this GitHub answers "Permission
            # denied (publickey)" while the key is present, valid and registered --
            # and `git push` fails for something that looks like a key problem but
            # is really a name problem. IdentitiesOnly stops ssh walking every key
            # first and tripping MaxAuthTries. Signing does NOT need this; it reads
            # the file directly. Only auth to github.com does.
            if ! grep -qs "IdentityFile ~/.ssh/devbox_agent" ~/.ssh/config; then
                umask 077
                cat >> ~/.ssh/config <<'SSHCFG'

Host github.com
    User git
    IdentityFile ~/.ssh/devbox_agent
    IdentitiesOnly yes
SSHCFG
                chmod 600 ~/.ssh/config
                echo "    ssh: github.com pinned to the devbox key"
            fi

            # gh reads config.yml from this directory. The sandbox masks hosts.yml
            # inside it, and masking a file under a MISSING parent leaves the parent
            # as a FILE -- after which every gh call dies with "not a directory",
            # which reads like a corrupt install rather than a sandbox artifact.
            mkdir -p ~/.config/gh
        elif [[ -f "$DOTFILES/config-git/personal" ]]; then
            git config --global user.signingkey "$(sed -n 's/^[[:space:]]*signingkey = //p' "$DOTFILES/config-git/personal")"
        fi
        git config --global gpg.format ssh
        git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

        # allowed_signers governs LOCAL verification only, independently of what
        # GitHub accepts. sign-push refuses to push unless `git log %G?` reports
        # G, so a correct signing key with a stale signers file still blocks the
        # workflow -- and the copied file lists only the Mac's keys.
        # Map each key to the ONE email whose account owns it. This used to add
        # devbox_agent under both addresses, which is why the crossed-key bug above
        # survived: a cross-mapped signers file makes `%G?` report G for a signature
        # GitHub will reject, so the local check agreed with nothing. Over-permissive
        # here does not merely fail to catch the error, it manufactures confidence.
        if [[ "$PLATFORM" == "linux" ]]; then
            mkdir -p ~/.config/git
            _add_signer() {   # $1 = email, $2 = pubkey path
                [[ -f "$2" ]] || return 0
                local _k; _k=$(awk '{print $2}' "$2")
                grep -qF "$1 " <(grep -F "$_k" ~/.config/git/allowed_signers 2>/dev/null) && return 0
                printf '%s %s\n' "$1" "$(cat "$2")" >> ~/.config/git/allowed_signers
                echo "    git: allowed_signers += $1 -> $(basename "$2")"
            }
            _add_signer andy@pezware.com ~/.ssh/devbox_agent_personal.pub
            _add_signer andy@iden2.com   ~/.ssh/devbox_agent.pub
            # Pre-2026-08-04 files cross-map devbox_agent onto andy@pezware.com.
            # Leave it: removing a signer can only turn a G into an N, and the
            # authoritative check is GitHub's, asserted in devbox-smoketest.
            unset -f _add_signer
        fi
        if [[ -f "$DOTFILES/config-git/work" ]]; then
            cp -v "$DOTFILES/config-git/work" ~/.config/git/work
            git config --global includeIf."gitdir:~/src/iden2/".path ~/.config/git/work

            # An include OVERRIDES the global, so setting user.signingkey globally
            # above does not reach ~/src/iden2/ -- the tracked work file carries the
            # Mac's `key::` value and silently wins there. Every iden2 commit then
            # fails with "Couldn't find key in agent?" while signing works fine
            # everywhere else, which is a maddening thing to debug.
            #
            # Found by an agent taking a real ticket, not by the smoke test: that
            # signs in a throwaway repo under /tmp, which never matches this
            # gitdir: condition. Same key, same email, only the form changes.
            if [[ "$PLATFORM" == "linux" && -f ~/.ssh/devbox_agent ]]; then
                git config --file ~/.config/git/work user.signingkey ~/.ssh/devbox_agent
                echo "    git: iden2 include re-pointed at the on-disk key (path form)"
            fi
        fi

        # gh wrapper: selects the fine-grained PAT matching the repo's owner.
        # Installed as ~/.local/bin/gh, which is ahead of the mise shim on PATH.
        # It reads ~/.config/0x58/credentials.env, which agents can read too. An
        # earlier version of this comment claimed excludedCommands let gh escape
        # the sandbox and read a file agents could not -- measured false: the
        # credentials deny applied anyway and gh could not run at all. Access is
        # granted explicitly now, and scoping is what bounds the damage.
        if [[ -f "$LINUX_DIR/gh-token-wrapper" ]]; then
            mkdir -p ~/.local/bin
            install -m 755 "$LINUX_DIR/gh-token-wrapper" ~/.local/bin/gh
            echo "    gh: token-selecting wrapper installed to ~/.local/bin/gh"
        fi

        # SessionStart hook: states the box's divergences before an agent can be
        # wrong about them. Wired in claude-settings.json, which names this
        # absolute path -- settings.json does not expand ~ in hook commands.
        #
        # This exists because the devbox-workflow skill was present, current, and
        # still did not fire on 2026-08-05: an agent read gh's own "run gh auth
        # login" and believed it. Skills are elected by the model; a hook is run
        # by the harness, which is the difference that matters for facts needed
        # before the model knows it needs them.
        if [[ -f "$LINUX_DIR/devbox-session-context" ]]; then
            mkdir -p ~/.local/bin
            install -m 755 "$LINUX_DIR/devbox-session-context" ~/.local/bin/devbox-session-context
            echo "    claude: SessionStart context hook installed"
        fi

        # systemd user unit for the Codex broker.
        #
        # Installed but NOT enabled: which workspaces get a broker is a per-machine
        # choice, and enabling an instance for a repo that is not cloned would just
        # fail on every boot. See dev/nodes/README.md for the enable step, which
        # also needs lingering.
        if [[ -f "$LINUX_DIR/codex-broker@.service" ]]; then
            mkdir -p ~/.config/systemd/user
            cp -v "$LINUX_DIR/codex-broker@.service" ~/.config/systemd/user/
            systemctl --user daemon-reload 2>/dev/null || true
        fi

        # Rootless podman's Docker-compatible API socket, for testcontainers.
        #
        # Enabled here, unlike the broker above, because it is not per-repo: it is
        # either wanted on this box or podman is not installed. Ships with podman,
        # so no unit file of ours to copy.
        #
        # --now needs a user bus, which a non-login shell does not have; the
        # XDG_RUNTIME_DIR fallback in bashrc is what makes this work when restore.sh
        # runs from the per-boot tmux session. Lingering must already be on or the
        # socket dies at logout and tests fail only when nobody is attached — see
        # dev/nodes/README.md.
        # Lingering first, and enabled rather than merely warned about. It lives in
        # /var/lib/systemd/linger on the ROOT disk, so every rebuild loses it while
        # ~/src survives on the volume -- the box looks fully restored and the user
        # manager still exits at logout. Everything user-scoped then dies with it:
        # podman.socket, and the per-boot tmux session. The symptom is horrible to
        # chase, because it only appears once nobody is attached.
        if ! loginctl show-user "$USER" -p Linger --value 2>/dev/null | grep -q yes; then
            if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
                sudo loginctl enable-linger "$USER" && echo "    systemd: lingering enabled (user units survive logout)"
            else
                echo "    systemd: WARNING lingering off and no sudo — run 'sudo loginctl enable-linger $USER'" >&2
            fi
        fi

        if command -v podman >/dev/null 2>&1; then
            if systemctl --user enable --now podman.socket 2>/dev/null; then
                echo "    podman: API socket enabled for testcontainers (humans/CI only)"
            else
                echo "    podman: socket NOT enabled — no user bus; run 'systemctl --user enable --now podman.socket' from a login shell" >&2
            fi
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

    # mise trust state lives under ~/.local/state on the ROOT disk, so a rebuild
    # loses it while the repos themselves survive on the volume. Every mise tool in
    # an untrusted repo then fails -- not one tool, all of them -- and mise reports
    # it as "error parsing config file", with the real reason on the NEXT line. The
    # headline blames TOML syntax for what is actually a trust prompt, which sends
    # you debugging a file that is perfectly valid.
    if command -v mise &>/dev/null; then
        for _cfg in ~/.config/mise/config.toml ~/src/*/*/.mise.toml ~/src/*/*/mise.toml; do
            [[ -f "$_cfg" ]] && mise trust "$_cfg" &>/dev/null && echo "    mise: trusted ${_cfg/#$HOME/\~}"
        done
        unset _cfg
    fi

    # nvim plugins (lazy.nvim auto-bootstraps on first launch). macOS only —
    # printing this on the devbox would advertise an editor that is not there.
    if [[ "$PLATFORM" == "macos" ]]; then
        echo "    nvim: run 'nvim' once to install plugins via lazy.nvim"
    fi

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
# --- Phase 3b: keeping ~/src current ---
setup_src_sync() {
    echo "==> src-sync (keep ~/src fast-forwarded)"

    mkdir -p ~/.local/bin
    local s
    for s in src-sync src-sync-remind; do
        [[ -f "$BIN_DIR/$s" ]] && install -m 755 "$BIN_DIR/$s" ~/.local/bin/"$s"
    done
    echo "    installed: ~/.local/bin/src-sync, ~/.local/bin/src-sync-remind"

    if [[ "$PLATFORM" == "linux" ]]; then
        # Automatic here, deliberately. There is no SSH agent on the devbox --
        # ~/.ssh/config pins an on-disk key -- so an unattended fetch cannot
        # produce a prompt, which is the one thing that would make a timer
        # obnoxious. Enabled, unlike the codex broker above, because it is not a
        # per-repo choice: it either applies to this machine's ~/src or to nothing.
        if [[ -f "$LINUX_DIR/src-sync.service" && -f "$LINUX_DIR/src-sync.timer" ]]; then
            mkdir -p ~/.config/systemd/user
            cp "$LINUX_DIR/src-sync.service" "$LINUX_DIR/src-sync.timer" ~/.config/systemd/user/
            systemctl --user daemon-reload 2>/dev/null || true
            if systemctl --user enable --now src-sync.timer 2>/dev/null; then
                echo "    systemd: src-sync.timer enabled (hourly, catches up after downtime)"
            else
                echo "    systemd: src-sync.timer NOT enabled — no user bus; run" >&2
                echo "             'systemctl --user enable --now src-sync.timer' from a login shell" >&2
            fi
        fi
    else
        # The Mac gets a REMINDER, not a sync, and the reason is the Secure
        # Enclave. Whether a git fetch costs a fingerprint is a per-key Secretive
        # setting that can change without touching this repo. Measured 2026-08-05
        # it is off, so an hourly sync WOULD work today -- and would start
        # throwing a biometric prompt every hour the moment it flips. An
        # unattended job that prompts trains you to dismiss it. The reminder needs
        # no key and no network, so it survives that setting either way.
        local src="$DOTFILES/launchd/com.0x58.src-sync-remind.plist"
        local plist=~/Library/LaunchAgents/com.0x58.src-sync-remind.plist
        if [[ -f "$src" ]]; then
            mkdir -p ~/Library/LaunchAgents ~/Library/Logs
            sed -e "s#SRC_SYNC_REMIND_PATH#$HOME/.local/bin/src-sync-remind#" \
                -e "s#SRC_SYNC_LOG#$HOME/Library/Logs/src-sync.log#" \
                "$src" > "$plist"
            # bootout before bootstrap: launchd refuses to bootstrap a label that
            # is already registered and reports it as a generic input/output
            # error, which reads like a malformed plist rather than "already
            # loaded". Doing this unconditionally makes re-running restore safe.
            launchctl bootout "gui/$UID/com.0x58.src-sync-remind" 2>/dev/null || true
            if launchctl bootstrap "gui/$UID" "$plist" 2>/dev/null; then
                echo "    launchd: src-sync-remind loaded (every 6h, silent unless something is stale)"
            else
                echo "    launchd: src-sync-remind NOT loaded — run" >&2
                echo "             launchctl bootstrap gui/$UID $plist" >&2
            fi
        fi
    fi
}

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
setup_src_sync
setup_pam_touchid
setup_linux_server
apply_macos_defaults
apply_keyboard_shortcuts
print_manual_steps
