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

if command_exists nodenv; then
  eval "$(nodenv init -)"
fi

if command_exists npx; then
  alias npx="npx --no-install"
fi

alias node-grep="grep -R --exclude-dir=node_modules --exclude-dir=public"

