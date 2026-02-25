#!/usr/bin/env zsh
autoload command_exists

if command_exists direnv; then
  zsh-defer eval "$(direnv hook zsh)"
fi
