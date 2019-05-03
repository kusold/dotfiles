#! /usr/bin/env bash

if command -v gem >/dev/null 2>&1; then
  echo "installing global ruby packages"
  gem install neovim
fi
