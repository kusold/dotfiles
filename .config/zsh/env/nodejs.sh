#!/usr/bin/env zsh

# Set a default in case `.env.private` isn't decrypted
export NPM_FONTAWESOME=""

export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/npmrc

if [[ -d "${HOME}/.local/share/npm/bin" ]]; then
  export PATH="${PATH}:${HOME}/.local/share/npm/bin"
fi
