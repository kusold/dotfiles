#!/usr/bin/env zsh
autoload command_exists

if command_exists yaourt; then
  alias upgrade-arch="yaourt -Syu --devel --aur --noconfirm"
fi
