#!/usr/bin/env zsh

autoload command_exists

if command_exists vagrant; then
  export VAGRANT_DEFAULT_PROVIDER=virtualbox
fi

