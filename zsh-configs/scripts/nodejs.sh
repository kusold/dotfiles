#!/usr/bin/env zsh
autoload command_exists

# Add nvm
if [[ -f "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR=$HOME/.nvm
  source $NVM_DIR/nvm.sh
  source $NVM_DIR/bash_completion
elif [[ -f "/usr/share/nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  source /usr/share/nvm/nvm.sh
  source /usr/share/nvm/bash_completion
fi

# Installs happen via dotbot now
#if command_exists npm; then
#  alias npm-install-globals="npm install -g grunt-cli eslint jshint jshint-jsx npm-shrinkwrap clone-org-repos"
#fi

alias node-grep="grep -R --exclude-dir=node_modules --exclude-dir=public"

