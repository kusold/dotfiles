#! /usr/bin/env bash

# install homebrew if it's missing
if ! command -v brew >/dev/null 2>&1; then
  echo "installing homebrew"
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# I don't keep this file in sync regularly
#if [ -f "$HOME/.Brewfile" ]; then
#  echo "installing brew packages from ~/.Brewfile"
#  brew bundle --global
#fi

