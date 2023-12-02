#!/usr/bin/env zsh
autoload command_exists

if command_exists brew; then
  # Don't let homebrew report google analytics
  export HOMEBREW_NO_ANALYTICS=1

  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi
