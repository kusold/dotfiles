#!/usr/bin/env zsh
autoload command_exists

# Add nvm
if [[ -f "/usr/share/nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  source /usr/share/nvm/nvm.sh
  source /usr/share/nvm/bash_completion
fi
if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR=$HOME/.nvm
  source $HOME/.nvm/nvm.sh
fi

if command_exists npm; then
  alias npm-install-globals="npm install -g grunt-cli eslint jshint npm-shrinkwrap clone-org-repos"
fi

alias node-grep="grep -R --exclude-dir=node_modules --exclude-dir=public"

