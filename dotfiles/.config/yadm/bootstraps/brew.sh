#! /usr/bin/env bash

# install homebrew if it's missing
if ! command -v brew >/dev/null 2>&1; then
  echo "installing homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# I don't keep this file in sync regularly
#if [ -f "$HOME/.Brewfile" ]; then
#  echo "installing brew packages from ~/.Brewfile"
#  brew bundle --global
#fi

