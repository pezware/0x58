# macOS specific configuration
#
# OWNED BY THE MAC. Sourced from the shared ~/.bashrc, which is installed verbatim
# on both machines and must stay platform-neutral. Put macOS-shaped settings here,
# not there.
#
# Its counterpart is bash/linux.bash. Where the two make OPPOSITE choices — the
# SSH agent and DO_NOT_TRACK — the reasoning is written on both sides. Read them
# together before changing either.

# Homebrew path
eval "$(/opt/homebrew/bin/brew shellenv)"

# MacOS specific aliases
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
# NOTE: the codex model pin deliberately lives in bashrc, not here. This file is
# sourced BELOW bashrc's alias section, so an alias defined here silently
# overrides the one there. That is how the retired 'gpt-5-codex' kept winning on
# macOS long after bashrc had moved on: `type codex` reported the stale model and
# the bashrc line looked correct. Keep model pinning in one place.
alias cc='claude'

# `cat` -> bat, on macOS only. On a remote box it actively gets in the way: bat
# paginates and adds line numbers and decorations, so reading a file in an ssh
# tmux pane produces output you cannot cleanly copy. It also muddies debugging —
# during sandbox verification `cat` of a denied path returned bat's formatting
# instead of the plain read failure, which made a working deny look ambiguous.
# Keep the real cat where you are inspecting things over a wire.
alias cat=bat

# --- Environment -------------------------------------------------------------
# These are hardcoded to macOS paths and were actively harmful when this file's
# contents still lived in the shared bashrc: /usr/libexec/java_home does not exist
# on Linux and errored on every interactive shell there.
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
# Counterpart: linux.bash deliberately leaves SSH_AUTH_SOCK alone so a forwarded
# agent survives. Here we pin it to Secretive's Secure Enclave agent.
export SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:/usr/local/bin:$PATH"
# Counterpart: linux.bash sets this to 0 for Claude Code Remote Control. The
# telemetry opt-out stays ON here; the Mac never needs Remote Control.
export DO_NOT_TRACK=1
# kind assumes docker unless told otherwise, and there is no docker on this Mac —
# the runtime is podman. OrbStack was removed but its docker context outlived it,
# so `kind get clusters` failed against a socket whose app no longer existed: the
# error named a missing file, not a missing provider, which reads like a broken
# install rather than the wrong backend. Podman support is still flagged upstream,
# so kind will not fall back to it on its own.
#
# Deliberately not in bashrc. The devbox runs podman too, but linux.bash is owned
# by that machine; this is the Mac speaking for the Mac.
export KIND_EXPERIMENTAL_PROVIDER=podman


# completion for macos
[ -f "$(brew --prefix)/bin/terraform" ] && complete -C "$(brew --prefix)/bin/terraform" terraform
[ -f "$(brew --prefix)/bin/vault" ] && complete -C "$(brew --prefix)/bin/vault" vault

for completion_file in \
  /opt/homebrew/etc/profile.d/bash_completion.sh \
  /opt/homebrew/etc/bash_completion \
  /opt/homebrew/etc/bash_completion.d/aws_bash_completer \
  /opt/homebrew/etc/bash_completion.d/git-completion.bash \
  /opt/homebrew/etc/bash_completion.d/git-prompt.sh \
  /opt/homebrew/etc/bash_completion.d/gh \
  /opt/homebrew/etc/bash_completion.d/google-cloud-sdk \
  /opt/homebrew/etc/bash_completion.d/kubectl \
  /opt/homebrew/etc/bash_completion.d/minikube \
  /opt/homebrew/opt/azure-cli/etc/bash_completion.d/az \
  /opt/homebrew/opt/fzf/shell/completion.bash \
  /opt/homebrew/opt/fzf/shell/key-bindings.bash \
  /opt/homebrew/opt/nvm/nvm.sh \
  /opt/homebrew/opt/nvm/etc/bash_completion.d/nvm \
  /opt/homebrew/opt/helm/etc/bash_completion.d/helm \
  /usr/local/etc/bash_completion \
  /etc/bash_completion; do
  if [ -f "$completion_file" ]; then
    . "$completion_file"
    break
  fi
done
