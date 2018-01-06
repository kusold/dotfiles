#!/usr/bin/env zsh
autoload command_exists

if command_exists git; then
  # Could be a git alias, but it had trouble finding pbcopy
  alias git-hash='git rev-parse HEAD && git rev-parse HEAD | pbcopy'
fi
