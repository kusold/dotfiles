#!/usr/bin/env zsh
autoload command_exists

# Ruby
if command_exists rbenv; then
  eval "$(rbenv init -)";
fi

# Source RVM
if [[ -s "${HOME}/.rvm/scripts/rvm" ]]; then
  source $HOME/.rvm/scripts/rvm
fi

if command_exists bundle; then
  alias be="bundle exec";
fi


