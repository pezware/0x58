# MacOS specific configurations

# Homebrew path
eval "$(/opt/homebrew/bin/brew shellenv)"

# MacOS specific aliases
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias codex='codex -m gpt-5-codex -c model_reasoning_effort="high"'
alias cc='claude'


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
