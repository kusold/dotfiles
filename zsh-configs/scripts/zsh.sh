#!/usr/bin/env zsh

# Reload zshrc.
if [[ -s "$HOME/.zshrc" ]]; then
  alias reload-zshrc="source $HOME/.zshrc"
  alias edit-zshrc="$EDITOR $HOME/.zshrc"
fi

