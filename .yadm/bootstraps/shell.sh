#! /usr/bin/env bash

if ! grep -q "$(command -v zsh)" /etc/shells; then
  echo "Setting default shell to $(command -v zsh)"
  sudo sh -c "echo $(command -v zsh) >> /etc/shells"
  chsh -s "$(command -v zsh)"
fi
