#! /usr/bin/env bash

if command -v pip3 >/dev/null 2>&1; then
  echo "installing global pip packages"
  pip3 install neovim --upgrade
fi

