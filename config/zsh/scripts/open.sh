#!/usr/bin/env zsh
autoload is_darwin
autoload is_linux

if is_darwin; then
  alias o='open'
elif is_linux; then
  alias o='xdg-open'
fi

