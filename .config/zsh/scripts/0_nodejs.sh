#!/usr/bin/env zsh
autoload command_missing
autoload command_exists

# Set a default in case `.env.private` isn't decrypted
export NPM_FONTAWESOME=""

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

if [[ -f "/usr/local/opt/node@10/bin/node" ]] && command_missing node; then
  echo "ADDING NODE 10 TO PATH"
  export PATH="/usr/local/opt/node@10/bin:$PATH"
  export LDFLAGS="-L/usr/local/opt/node@10/lib"
  export CPPFLAGS="-I/usr/local/opt/node@10/include"
fi

if command_exists npx; then
  alias npx="npx --no-install"
fi

alias node-grep="grep -R --exclude-dir=node_modules --exclude-dir=public"

