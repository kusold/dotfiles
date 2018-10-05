#!/usr/bin/env zsh
autoload command_exists

if command_exists base16_eighties; then
  alias dark=base16_eighties
fi

if command_exists base16_solarized-light; then
  alias light=base16_solarized-light
fi
