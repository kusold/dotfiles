#! /usr/bin/env bash

if command -v pip2.7 >/dev/null 2>&1; then
  echo "installing global pip2.7 packages"
  pip2.7 install pynvim neovim --upgrade
fi

if command -v pip3 >/dev/null 2>&1; then
  echo "installing global pip3 packages"
  pip3 install pynvim neovim --upgrade

  # vim script linting
  pip3 install vim-vint --upgrade
fi

