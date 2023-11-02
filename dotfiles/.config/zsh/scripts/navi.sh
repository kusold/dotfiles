#!/usr/bin/env zsh
autoload command_exists

# Interactive cheatsheet
# https://github.com/denisidoro/navi

if command_exists navi; then
  eval "$(navi widget zsh)"
fi
