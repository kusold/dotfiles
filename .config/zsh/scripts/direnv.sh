#!/usr/bin/env zsh

if command -v direnv >/dev/null 2>&1; then
  zsh-defer eval "$(direnv hook zsh)"
fi
